// Finite live FIFO transport for the public ports of protocol_bridge_pair.
// No hierarchy or actor state is read. The host supplies every command/reply decision.
#include "Vprotocol_bridge_pair.h"
#include "verilated.h"
#include "framed_fifo_stream.h"
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <stdexcept>
#include <string>
#include <thread>
#include <unistd.h>

// Independent physical streams share this simulator clock; sessions never survive reset.
int main(int argc,char**argv){
    if(argc!=2&&argc!=3)return 2;
    const bool cancel_chatter=argc==3&&std::string(argv[2])=="--cancel-chatter";
    if(argc==3&&!cancel_chatter)return 2;
    try{
        std::string dir=argv[1];Verilated::commandArgs(argc,argv);
        Vprotocol_bridge_pair dut;FramedFifoStream a(dir+"/role0"),b(dir+"/role1");
        auto began=std::chrono::steady_clock::now();
        for(uint64_t cycle=0;cycle<(cancel_chatter?2000000u:200000u);cycle++){
            bool reset=cycle<8;
            if(!reset){a.pump();b.pump();}
            dut.clk=0;dut.reset=reset;dut.retire=0;
            dut.s0_data=a.word;dut.s0_last=a.last;dut.s0_valid=!reset&&a.valid;
            dut.s1_data=b.word;dut.s1_last=b.last;dut.s1_valid=!reset&&b.valid;
            dut.m0_ready=!reset&&a.output_ready()&&cycle%19>=7;
            dut.m1_ready=!reset&&b.output_ready()&&cycle%23>=11;
            dut.eval();
            if(!reset){
                if(dut.fault)throw std::runtime_error("source or bridge fault");
                a.sample(dut.s0_ready,dut.m0_data,dut.m0_valid,dut.m0_last,dut.m0_ready,cycle);
                b.sample(dut.s1_ready,dut.m1_data,dut.m1_valid,dut.m1_last,dut.m1_ready,cycle);
            }
            dut.clk=1;dut.eval();
            if(cycle%64==0){
                if(access((dir+"/done").c_str(),F_OK)==0){
                    if(!cancel_chatter&&(a.input_pending()||b.input_pending()))
                        throw std::runtime_error("pending application input");
                    if(cancel_chatter){
                        // Host requested transport closure; retire before closing peer FIFO endpoints.
                        dut.clk=0;dut.retire=1;dut.eval();
                        if(dut.s0_ready||dut.s1_ready||dut.m0_valid||dut.m1_valid)
                            throw std::runtime_error("retired public handshake");
                        printf("RETIRED pending_input_bytes=%zu,%zu held_beats=%u,%u\n",
                            a.pending_input_bytes(),b.pending_input_bytes(),unsigned(a.valid),unsigned(b.valid));
                    }
                    if(a.stalls<50||b.stalls<50)throw std::runtime_error("missing independent stalls");
                    printf("PASS framed pair cycles=%llu stalls=%llu,%llu words=%llu,%llu\n",
                        (unsigned long long)cycle,(unsigned long long)a.stalls,(unsigned long long)b.stalls,
                        (unsigned long long)a.outputs,(unsigned long long)b.outputs);
                    dut.final();return 0;
                }
                if(std::chrono::steady_clock::now()-began>std::chrono::seconds(cancel_chatter?120:60))throw std::runtime_error("wall deadline");
                std::this_thread::sleep_for(std::chrono::microseconds(100));
            }
        }
        throw std::runtime_error("cycle horizon");
    }catch(const std::exception&e){fprintf(stderr,"FAIL framed pair: %s\n",e.what());return 1;}
}
