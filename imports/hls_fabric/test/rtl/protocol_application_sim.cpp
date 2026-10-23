// Finite live FIFO transport for the public ports of protocol_application_top.
// No hierarchy or actor state is read. The host supplies every command/reply decision.
#include "Vprotocol_application_top.h"
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

// The clock label is simulation time only; no throughput claim uses this rate.
int main(int argc,char**argv){
    if(argc!=2)return 2;
    try{
        std::string dir=argv[1];
        Verilated::commandArgs(argc,argv);
        Vprotocol_application_top dut;
        Stream app(dir+"/app");
        auto began=std::chrono::steady_clock::now();
        uint64_t cycle=0,activation=0;
        for(;cycle<4000000;cycle++){
            bool reset=cycle<8;
            if(!reset){app.pump();}
            dut.clk=0;dut.reset=reset;
            dut.s_app_tdata=app.word;dut.s_app_tlast=app.last;dut.s_app_tvalid=!reset&&app.valid;
            dut.m_app_tready=!reset&&app.tx.size()<65532&&cycle%19>=7;
            dut.eval();
            if(!reset){
                if(dut.ingress_fault||dut.actor_0_failure||dut.actor_1_failure||dut.actor_2_failure||dut.actor_3_failure||dut.actor_0_fault||dut.actor_1_fault||dut.actor_2_fault||dut.actor_3_fault)throw std::runtime_error("source fault");
                app.sample(dut.s_app_tready,dut.m_app_tdata,dut.m_app_tvalid,dut.m_app_tlast,dut.m_app_tready,cycle);
            }
            dut.clk=1;dut.eval();
            if(dut.running&&!activation)activation=cycle;
            if(cycle%64==0){
                if(access((dir+"/done").c_str(),F_OK)==0){
                    if(app.valid||!app.rx.empty()||app.phase)throw std::runtime_error("pending application input");
                    printf("PASS live application cycles=%llu activation=%llu input_words=%llu output_words=%llu output_stalls=%llu\n",(unsigned long long)cycle,(unsigned long long)activation,(unsigned long long)app.inputs,(unsigned long long)app.outputs,(unsigned long long)app.stalls);
                    dut.final();return 0;
                }
                if(std::chrono::steady_clock::now()-began>std::chrono::seconds(120))throw std::runtime_error("wall deadline");
                std::this_thread::sleep_for(std::chrono::microseconds(100));
            }
        }
        throw std::runtime_error("cycle horizon");
    }catch(const std::exception&e){fprintf(stderr,"FAIL live application: %s\n",e.what());return 1;}
}
