// Finite live FIFO transport for the public ports of protocol_application_top.
// No hierarchy or actor state is read. The host supplies every command/reply decision.
#include "Vprotocol_bridge_pair.h"
#include "verilated.h"
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <stdexcept>
#include <string>
#include <thread>
#include <cerrno>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

// Bounded transport queues and framing state for one independent public stream.
struct Stream {
    int input, output;
    std::deque<uint8_t> rx, tx;
    unsigned phase=0, remaining=0;
    uint32_t word=0, prior=0;
    bool valid=false,last=false,blocked=false,prior_last=false;
    uint64_t inputs=0,outputs=0,stalls=0;
    FILE *trace;
    explicit Stream(const std::string& prefix) {
        if (mkfifo((prefix+"_tx").c_str(),0600) || mkfifo((prefix+"_rx").c_str(),0600))
            throw std::runtime_error("fresh FIFO creation failed");
        input=open((prefix+"_tx").c_str(),O_RDWR|O_NONBLOCK);
        output=open((prefix+"_rx").c_str(),O_RDWR|O_NONBLOCK);
        trace=fopen((prefix+"-words.log").c_str(),"wx");
        if(input<0||output<0||!trace) throw std::runtime_error("FIFO open failed");
    }
    ~Stream(){close(input);close(output);fclose(trace);}
    // Partial OS reads/writes never change the held public beat.
    void pump(){
        uint8_t bytes[4096];
        if(rx.size()+sizeof(bytes)<=65536){
            ssize_t n=read(input,bytes,sizeof(bytes));
            if(n>0)rx.insert(rx.end(),bytes,bytes+n);
            else if(n<0&&errno!=EAGAIN&&errno!=EINTR)throw std::runtime_error("FIFO read");
        }
        size_t count=std::min(tx.size(),sizeof(bytes));
        for(size_t i=0;i<count;i++)bytes[i]=tx[i];
        if(count){ssize_t n=write(output,bytes,count);
            if(n>0)for(ssize_t i=0;i<n;i++)tx.pop_front();
            else if(n<0&&errno!=EAGAIN&&errno!=EINTR)throw std::runtime_error("FIFO write");}
        if(!valid&&rx.size()>=4){
            word=0;for(unsigned i=0;i<4;i++){word|=uint32_t(rx.front())<<(8*i);rx.pop_front();}
            valid=true;
            if(phase==0){last=false;phase=1;}
            else if(phase==1){remaining=word&255;last=remaining==0;phase=last?0:2;}
            else{last=--remaining==0;if(last)phase=0;}
        }
    }
    // Verify ready/valid stability and retain only accepted words.
    void sample(bool in_ready,uint32_t out_word,bool out_valid,bool out_last,bool out_ready,uint64_t cycle){
        if(blocked&&(!out_valid||out_word!=prior||out_last!=prior_last))throw std::runtime_error("stalled output changed");
        blocked=out_valid&&!out_ready;prior=out_word;prior_last=out_last;
        if(blocked)stalls++;
        if(valid&&in_ready){fprintf(trace,"I %llu %08x %u\n",(unsigned long long)cycle,word,last);inputs++;valid=false;}
        if(out_valid&&out_ready){
            if(tx.size()>65532)throw std::runtime_error("output capacity");
            fprintf(trace,"O %llu %08x %u\n",(unsigned long long)cycle,out_word,out_last);outputs++;
            for(unsigned i=0;i<4;i++)tx.push_back(uint8_t(out_word>>(8*i)));
        }
    }
};

// Independent physical streams share this simulator clock; sessions never survive reset.
int main(int argc,char**argv){
    if(argc!=2)return 2;
    try{
        std::string dir=argv[1];Verilated::commandArgs(argc,argv);
        Vprotocol_bridge_pair dut;Stream a(dir+"/role0"),b(dir+"/role1");
        auto began=std::chrono::steady_clock::now();
        for(uint64_t cycle=0;cycle<200000;cycle++){
            bool reset=cycle<8;
            if(!reset){a.pump();b.pump();}
            dut.clk=0;dut.reset=reset;dut.retire=0;
            dut.s0_data=a.word;dut.s0_last=a.last;dut.s0_valid=!reset&&a.valid;
            dut.s1_data=b.word;dut.s1_last=b.last;dut.s1_valid=!reset&&b.valid;
            dut.m0_ready=!reset&&a.tx.size()<65532&&cycle%19>=7;
            dut.m1_ready=!reset&&b.tx.size()<65532&&cycle%23>=11;
            dut.eval();
            if(!reset){
                if(dut.fault)throw std::runtime_error("source or bridge fault");
                a.sample(dut.s0_ready,dut.m0_data,dut.m0_valid,dut.m0_last,dut.m0_ready,cycle);
                b.sample(dut.s1_ready,dut.m1_data,dut.m1_valid,dut.m1_last,dut.m1_ready,cycle);
            }
            dut.clk=1;dut.eval();
            if(cycle%64==0){
                if(access((dir+"/done").c_str(),F_OK)==0){
                    if(a.valid||!a.rx.empty()||a.phase||b.valid||!b.rx.empty()||b.phase)
                        throw std::runtime_error("pending application input");
                    if(a.stalls<50||b.stalls<50)throw std::runtime_error("missing independent stalls");
                    printf("PASS framed pair cycles=%llu stalls=%llu,%llu words=%llu,%llu\n",
                        (unsigned long long)cycle,(unsigned long long)a.stalls,(unsigned long long)b.stalls,
                        (unsigned long long)a.outputs,(unsigned long long)b.outputs);
                    dut.final();return 0;
                }
                if(std::chrono::steady_clock::now()-began>std::chrono::seconds(60))throw std::runtime_error("wall deadline");
                std::this_thread::sleep_for(std::chrono::microseconds(100));
            }
        }
        throw std::runtime_error("cycle horizon");
    }catch(const std::exception&e){fprintf(stderr,"FAIL framed pair: %s\n",e.what());return 1;}
}
