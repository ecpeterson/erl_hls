#include "Vprotocol_domains_stream.h"
#include "framed_fifo_endpoint.h"
#include <array>
#include <chrono>
#include <optional>
#include <thread>

// The finite transport stores one beat in either direction. Saved diagnostic
// copies are used only for explicitly requested stale-identity injection.
struct DataBeat {
    uint64_t generation;
    uint32_t sequence;
    uint8_t slot;
    std::array<uint32_t,21> frame;
};
struct CreditBeat { uint64_t generation; uint32_t sequence; };

// Controls choose delivery schedules; only public handshakes change queue ownership.
class Crossing {
    Vprotocol_domains_stream& core;
    GenerationControl data_control, credit_control;
    std::optional<DataBeat> data, oldest_data;
    std::optional<CreditBeat> credit, oldest_credit;
    bool inject_data=false, inject_credit=false, data_done=false, credit_done=false;
    FILE* trace;
    std::string directory;
public:
    explicit Crossing(Vprotocol_domains_stream& core, const std::string& directory):
        core(core), data_control(directory+"/crossing_data_delivery"),
        credit_control(directory+"/crossing_credit_delivery"), directory(directory) {
        trace=fopen((directory+"/crossing-edges.log").c_str(),"wx");
        if(!trace) throw std::runtime_error("crossing trace");
    }
    ~Crossing() { fclose(trace); }
    // Arming is distinct from a later retained-packet/drop acknowledgement.
    void armed(const char* name, uint64_t value) {
        FILE* output=fopen((directory+"/"+name+".armed").c_str(),"w");
        if(!output) throw std::runtime_error("crossing control arming");
        fprintf(output,"%llu\n",(unsigned long long)value);fclose(output);
    }
    // There is no same-edge transport bypass, and the independent periodic stalls are finite.
    void drive(uint64_t cycle) {
        if(cycle%256==0) {
            if(data_control.poll()) armed("crossing_data_delivery",data_control.generation());
            if(credit_control.poll()) armed("crossing_credit_delivery",credit_control.generation());
        }
        auto dm=data_control.generation(), cm=credit_control.generation();
        if(dm==3 && !data_done && data && data->generation>1 && data->sequence==1) {
            if(!oldest_data || oldest_data->sequence!=1) throw std::runtime_error("missing old data");
            inject_data=true;
        }
        if(cm==3 && !credit_done && credit && credit->generation>1 && credit->sequence==1) {
            if(!oldest_credit || oldest_credit->sequence!=1) throw std::runtime_error("missing old credit");
            inject_credit=true;
        }
        core.ch_0_data_tx_ready=!data && cycle%5!=1;
        core.ch_0_ack_tx_ready=!credit && cycle%7!=2;
        core.ch_0_data_valid=data.has_value() && dm!=1;
        if(data) {
            auto beat=inject_data?*oldest_data:*data;
            core.ch_0_data_generation=beat.generation; core.ch_0_data_sequence=beat.sequence;
            core.ch_0_data_slot=beat.slot;
            for(unsigned i=0;i<21;i++) core.ch_0_data_frame[i]=beat.frame[i];
        }
        core.ch_0_credit_valid=credit.has_value() && cm!=1;
        if(credit) {
            auto beat=inject_credit?*oldest_credit:*credit;
            core.ch_0_credit_generation=beat.generation; core.ch_0_credit_sequence=beat.sequence;
        }
        if(dm==1 && data) data_control.observe(1,true);
        if(cm==1 && credit) credit_control.observe(1,true);
        if(dm==2) data_control.observe(2,true);
        if(cm==2) credit_control.observe(2,true);
    }
    // Trace old-edge acceptances, including proof that each requested replay was dropped.
    void sample(uint64_t cycle) {
        if(core.ch_0_fault) throw std::runtime_error("channel kernel fault");
        if(core.ch_0_data_valid && core.ch_0_data_ready) {
            fprintf(trace,"DATA %llu %llu %u %u\n",(unsigned long long)cycle,
                (unsigned long long)core.ch_0_data_generation,core.ch_0_data_sequence,core.ch_0_data_drop);
            if(inject_data) {
                if(!core.ch_0_data_drop || !data || data->generation==oldest_data->generation)
                    throw std::runtime_error("eligible stale data was not excluded");
                inject_data=false;data_done=true;data_control.observe(3,true);
            } else data.reset();
        }
        if(core.ch_0_credit_valid && core.ch_0_credit_ready) {
            fprintf(trace,"CREDIT %llu %llu %u %u\n",(unsigned long long)cycle,
                (unsigned long long)core.ch_0_credit_generation,core.ch_0_credit_sequence,core.ch_0_credit_drop);
            if(inject_credit) {
                if(!core.ch_0_credit_drop || !credit || credit->generation==oldest_credit->generation)
                    throw std::runtime_error("eligible stale credit was not excluded");
                inject_credit=false;credit_done=true;credit_control.observe(3,true);
            } else credit.reset();
        }
        if(core.ch_0_tx_valid && core.ch_0_data_tx_ready) {
            if(data) throw std::runtime_error("data transport capacity");
            DataBeat beat{core.ch_0_tx_generation,core.ch_0_tx_sequence,core.ch_0_tx_slot,{}};
            for(unsigned i=0;i<21;i++) beat.frame[i]=core.ch_0_tx_frame[i];
            data=beat; if(!oldest_data) oldest_data=beat;
            fprintf(trace,"TX %llu %llu %u\n",(unsigned long long)cycle,(unsigned long long)beat.generation,beat.sequence);
        }
        if(core.ch_0_ack_valid && core.ch_0_ack_tx_ready) {
            if(credit) throw std::runtime_error("credit transport capacity");
            CreditBeat beat{core.ch_0_ack_generation,core.ch_0_ack_sequence};
            credit=beat;if(!oldest_credit) oldest_credit=beat;
            fprintf(trace,"ACK %llu %llu %u\n",(unsigned long long)cycle,(unsigned long long)beat.generation,beat.sequence);
        }
    }
};

// The test controls deployment sessions and transport delivery; all lifecycle and
// binding commands arrive through production broker streams from Erlang.
int main(int argc,char** argv) {
    Verilated::commandArgs(argc,argv);
    if(argc!=3) return 2;
    try {
        std::string directory=argv[1]; unsigned accepted=std::stoul(argv[2]);
        Vprotocol_domains_stream core;
        core.clk=0;core.reset=1;
        core.domain_0_domain_reset=core.domain_1_domain_reset=core.domain_2_domain_reset=0;
        Endpoint channel(SESSION(channel),directory+"/channel0");
        channel.add(LANE(channel,management),"management");
        Endpoint a(SESSION(domain_0),directory+"/domain0");
        a.add(LANE(domain_0,management),"management");a.add(LANE(domain_0,application),"application");
        Endpoint b(SESSION(domain_1),directory+"/domain1");
        b.add(LANE(domain_1,management),"management");b.add(LANE(domain_1,application),"application");
        Endpoint c(SESSION(domain_2),directory+"/domain2");
        c.add(LANE(domain_2,management),"management");c.add(LANE(domain_2,application),"application");
        std::vector<Endpoint*> endpoints={&channel,&a,&b,&c};
        GenerationControl drop_control(directory+"/channel0_drop_bind_reply");
        bool drop_armed=false,dropped=false;
        channel.lanes[0]->fifo->filter_output([&](const std::vector<uint32_t>& packet) {
            if(drop_armed && !dropped && packet.size()==16 && packet[6]==accepted && packet[14]==1) {
                dropped=true;
                FILE* output=fopen((directory+"/channel0_drop_bind_reply.observed").c_str(),"w");
                if(!output) throw std::runtime_error("drop observation");
                fputs("1\n",output);fclose(output);return false;
            }
            return true;
        });
        Crossing crossing(core,directory);
        uint64_t finish=0;
        auto start=std::chrono::steady_clock::now();
        for(uint64_t cycle=0;cycle<50000000;++cycle) {
            core.reset=cycle<4;
            if(cycle%256==0 && drop_control.poll()) {
                if(drop_control.generation()!=1) throw std::runtime_error("unsupported drop control");
                drop_armed=true;drop_control.observe(1,true);
            }
            for(auto endpoint:endpoints) endpoint->drive(cycle);
            crossing.drive(cycle);
            core.clk=0;core.eval();
            for(auto endpoint:endpoints) endpoint->sample(cycle);
            crossing.sample(cycle);
            core.clk=1;core.eval();
            for(auto endpoint:endpoints) endpoint->observe();
            if(cycle%256==0) {
                if(!finish && access((directory+"/finished").c_str(),F_OK)==0) finish=cycle+256;
                if(std::chrono::steady_clock::now()-start>std::chrono::seconds(120))
                    throw std::runtime_error("bounded cross-domain stream timeout");
                std::this_thread::sleep_for(std::chrono::microseconds(500));
            }
            if(finish && cycle>=finish) {
                printf("PASS cross-domain stream RTL: cycles=%llu\n",(unsigned long long)cycle);return 0;
            }
        }
        throw std::runtime_error("bounded cross-domain stream clocks");
    } catch(const std::exception& failure) {
        fprintf(stderr,"FAIL cross-domain stream RTL: %s\n",failure.what());return 1;
    }
}
