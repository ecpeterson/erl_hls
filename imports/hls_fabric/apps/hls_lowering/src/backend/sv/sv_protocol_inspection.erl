-module(sv_protocol_inspection).
-moduledoc "Renders the inspection pins and connections used by sv_protocol_application. Reuses the shared debug route and query service; no process-state interpretation or source inspection occurs in this SystemVerilog adapter.".

%% Wrapper inspection declarations and connections.
-export([ports/1, body/1]).

-doc "Adds the existing debug stream only when a process manifest is present.".
-spec ports(none | map()) -> iodata().
ports(none) ->
    [];
ports(_) ->
    ",input wire [31:0] s_dbg_tdata,input wire [3:0] s_dbg_tkeep,input wire s_dbg_tlast,s_dbg_tvalid,output wire s_dbg_tready,output wire [31:0] m_dbg_tdata,output wire [3:0] m_dbg_tkeep,output wire m_dbg_tlast,m_dbg_tvalid,input wire m_dbg_tready".

-doc "Connects one addressed 128-bit metadata observation to endpoint 2. The existing service retains a coherent pre-edge sample through output stalls; its reset cancels outstanding replies. This adapter contains no behavioral Verilog. No debug signal controls the application.".
-spec body(none | map()) -> iodata().
body(none) ->
    [];
body(#{<<"resources">> := Resources, <<"fingerprint">> := Hash}) ->
    N = integer_to_list(length(Resources)),
    H = integer_to_list(binary:decode_unsigned(binary:decode_hex(Hash), little), 16),
    [
        "wire [31:0] debug_request,debug_response;wire [3:0] debug_request_keep,debug_response_keep;\n",
        "wire debug_request_last,debug_request_valid,debug_request_ready,debug_response_last,debug_response_valid,debug_response_ready;\n",
        "hls_debug_route #(.PORTS(1),.ENDPOINTS(16'd2)) diagnostic_route(.clk(clk),.reset(reset),\n",
        ".s_data(s_dbg_tdata),.s_keep(s_dbg_tkeep),.s_last(s_dbg_tlast),.s_valid(s_dbg_tvalid),.s_ready(s_dbg_tready),\n",
        ".m_data(m_dbg_tdata),.m_keep(m_dbg_tkeep),.m_last(m_dbg_tlast),.m_valid(m_dbg_tvalid),.m_ready(m_dbg_tready),\n",
        ".request_data(debug_request),.request_keep(debug_request_keep),.request_last(debug_request_last),.request_valid(debug_request_valid),.request_ready(debug_request_ready),\n",
        ".response_data(debug_response),.response_keep(debug_response_keep),.response_last(debug_response_last),.response_valid(debug_response_valid),.response_ready(debug_response_ready));\n",
        "hls_topology_debug #(.RESOURCES(",
        N,
        "),.CHANNELS(0),.ACTORS(",
        N,
        "),.FINGERPRINT(256'h",
        H,
        ")) diagnostic_queries(.clk(clk),.reset(reset),\n",
        ".probe_address(inspect_address),.probe_value(inspect_value),\n",
        ".s_data(debug_request),.s_keep(debug_request_keep),.s_last(debug_request_last),.s_valid(debug_request_valid),.s_ready(debug_request_ready),\n",
        ".m_data(debug_response),.m_keep(debug_response_keep),.m_last(debug_response_last),.m_valid(debug_response_valid),.m_ready(debug_response_ready));\n"
    ].
