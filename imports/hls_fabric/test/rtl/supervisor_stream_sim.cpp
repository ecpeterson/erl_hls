#include "Vprotocol_supervisor_stream.h"
#include "verilated.h"
#include "framed_fifo_endpoint.h"
#include <chrono>
#include <memory>
#include <thread>
#include <vector>

// One clock advances parent policy and both child datapaths irrespective of host stalls.
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc != 2) return 2;
    try {
        std::string directory = argv[1];
        Vprotocol_supervisor_stream core;
        core.clk = 0; core.reset = 1;
        Endpoint parent(SESSION(parent),directory + "/parent");
        parent.add(LANE(parent,management),"management");
        Endpoint a(SESSION(child_0),directory + "/domain0");
        a.add(LANE(child_0,management),"management"); a.add(LANE(child_0,application),"application");
        Endpoint b(SESSION(child_1),directory + "/domain1");
        b.add(LANE(child_1,management),"management"); b.add(LANE(child_1,application),"application");
        std::vector<Endpoint*> endpoints = {&parent,&a,&b};
        auto start = std::chrono::steady_clock::now();
        uint64_t finish = 0;
        for (uint64_t cycle=0; cycle<50000000; ++cycle) {
            core.reset = cycle < 4;
            for (auto e : endpoints) e->drive(cycle);
            core.clk=0; core.eval();
            for (auto e : endpoints) e->sample(cycle);
            core.clk=1; core.eval();
            for (auto e : endpoints) e->observe();
            if (cycle%256==0) {
                if (!finish && access((directory+"/finished").c_str(),F_OK)==0) finish=cycle+256;
                if (std::chrono::steady_clock::now()-start > std::chrono::seconds(90))
                    throw std::runtime_error("bounded supervisor stream timeout");
                std::this_thread::sleep_for(std::chrono::microseconds(500));
            }
            if (finish && cycle>=finish) {
                printf("PASS supervisor stream RTL: cycles=%llu\n",(unsigned long long)cycle);
                return 0;
            }
        }
        throw std::runtime_error("bounded supervisor stream clocks");
    } catch(const std::exception& failure) {
        fprintf(stderr,"FAIL supervisor stream RTL: %s\n",failure.what()); return 1;
    }
}
