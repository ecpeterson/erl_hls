"""Optional public debug-stream wiring for the common application simulation harness."""


def debug_fragments(enabled: bool) -> dict[str,str]:
    """Drive independent stalls and compare application ports cycle-for-cycle with an unqueried twin."""
    if not enabled:return dict.fromkeys(['INIT','PUMP','INPUT','CONTROL','SAMPLE','EDGE','FINISH'],'')
    return {
        'INIT':'\n        Stream debug(dir+"/debug"); Vprotocol_application_top control;',
        'PUMP':'            if(!reset)debug.pump();\n',
        'INPUT':'''
            dut.s_dbg_tdata=debug.word;dut.s_dbg_tkeep=15;dut.s_dbg_tlast=debug.last;
            dut.s_dbg_tvalid=!reset&&debug.valid;dut.m_dbg_tready=!reset&&debug.tx.size()<65532&&cycle%71>=43;
''',
        'CONTROL':'''
            control.clk=0;control.reset=reset;control.s_app_tdata=dut.s_app_tdata;
            control.s_app_tlast=dut.s_app_tlast;control.s_app_tvalid=dut.s_app_tvalid;control.m_app_tready=dut.m_app_tready;
            control.s_dbg_tdata=0;control.s_dbg_tkeep=15;control.s_dbg_tlast=0;control.s_dbg_tvalid=0;control.m_dbg_tready=1;control.eval();
            if(dut.s_app_tready!=control.s_app_tready||dut.m_app_tvalid!=control.m_app_tvalid||
               dut.running!=control.running||(dut.m_app_tvalid&&
               (dut.m_app_tdata!=control.m_app_tdata||dut.m_app_tlast!=control.m_app_tlast)))
                throw std::runtime_error("debug changed application behavior");
''',
        'SAMPLE':'            if(!reset)debug.sample(dut.s_dbg_tready,dut.m_dbg_tdata,dut.m_dbg_tvalid,dut.m_dbg_tlast,dut.m_dbg_tready,cycle);\n',
        'EDGE':'control.clk=1;control.eval();',
        'FINISH':'''
                    if(debug.valid||!debug.rx.empty()||debug.phase||!debug.inputs||!debug.outputs||!debug.stalls)
                        throw std::runtime_error("incomplete debug witness");
                    printf("PASS passive inspection input_words=%llu output_words=%llu output_stalls=%llu\\n",
                        (unsigned long long)debug.inputs,(unsigned long long)debug.outputs,(unsigned long long)debug.stalls);
                    control.final();
'''}
