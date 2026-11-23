// Finite live FIFO transport for the public ports of protocol_bridge_top.
// No hierarchy or actor state is read. The host supplies every command/reply decision.
#include "Vprotocol_bridge_top.h"
#include "verilated.h"
#include "framed_fifo_stream.h"
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <stdexcept>
#include <string>
#include <thread>
#include <unistd.h>

// The clock label is simulation time only; no throughput claim uses this rate.
int main(int argc,char**argv){
    if(argc!=2)return 2;
    try{
        std::string dir=argv[1];
        Verilated::commandArgs(argc,argv);
        Vprotocol_bridge_top dut;
        FramedFifoStream app(dir+"/app");
        auto began=std::chrono::steady_clock::now();
        uint64_t cycle=0,activation=0;
        for(;cycle<4000000;cycle++){
            bool reset=cycle<8;
            if(!reset){app.pump();}
            dut.clk=0;dut.reset=reset;dut.retire=0;
            dut.s_app_tdata=app.word;dut.s_app_tlast=app.last;dut.s_app_tvalid=!reset&&app.valid;
            dut.m_app_tready=!reset&&app.output_ready()&&cycle%19>=7;
            dut.eval();
            if(!reset){
                if(dut.fault)throw std::runtime_error("source fault "+std::to_string(dut.fault));
                app.sample(dut.s_app_tready,dut.m_app_tdata,dut.m_app_tvalid,dut.m_app_tlast,dut.m_app_tready,cycle);
            }
            dut.clk=1;dut.eval();
            if(dut.running&&!activation)activation=cycle;
            if(cycle%64==0){
                if(access((dir+"/done").c_str(),F_OK)==0){
                    dut.clk=0;dut.retire=1;dut.eval();
                    if(dut.s_app_tready||dut.m_app_tvalid)throw std::runtime_error("retired handshake");
                    if(app.stalls<50)throw std::runtime_error("missing output stalls");
                    printf("RETIRED pending_input_bytes=%zu held_beats=%u\n",app.pending_input_bytes(),unsigned(app.valid));
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
