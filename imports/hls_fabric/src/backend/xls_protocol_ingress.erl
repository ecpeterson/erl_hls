-module(xls_protocol_ingress).
-moduledoc "Emits source-bound constant tables for the shared DSLX rectangle ingress implementation. All clock behavior resides in protocol_ingress.x.".
-export([emit/1, write/2]).

-doc "Writes a fresh ingress.x beside transport.x from the checked hls_protocol_control plan. Tables retain dense actor identities, coordinates and exact schema masks. Emits no behavioral Verilog and adds no state beyond the shared frame, pending bits and fault.".
-spec write(map(),file:filename()) -> ok.
write(Plan, Directory) ->
    file:write_file(filename:join(Directory, "ingress.x"), emit(Plan), [exclusive]).

-doc "Returns ingress DSLX bytes from a checked plan and the installed template. Dense identities, coordinates and schema masks are unchanged; no output files are created.".
-spec emit(map()) -> iodata().
emit(#{kind:=rectangle,actors:=N,width:=W,height:=H,targets:=Targets}) ->
    D=lists:max([length(Domains)||#{domains:=Domains}<-Targets]),
    {ok,Template}=file:read_file(filename:join(code:priv_dir(hls_fabric),"xls/templates/protocol_ingress.x.in")),
    Source=["import protocol_ingress as control;\nimport axis;\nconst ACTORS = u32:",n(N),";\n",
        "const WIDTH = u32:",n(W),";\nconst HEIGHT = u32:",n(H),";\n",
        "const TARGETS = control::Target<ACTORS,u32:",n(D),">[",n(length(Targets)),"]:[\n",
        [target(T,N,D)||T<-Targets],"];\n",Template],
    Source.

%% Unused point/domain entries are explicitly invalid, never wildcard encodings.
-spec target(map(),pos_integer(),pos_integer()) -> iodata().
target(#{recipients:=Recipients,domains:=Domains},N,D) ->
    ["control::Target { points: [",
     lists:join(",",[case [P||P=#{index:=J}<-Recipients,J=:=I] of
       [#{x:=X,y:=Y}]->["control::Point { present:true,x:u16:",n(X),",y:u16:",n(Y)," }"];
       []->"zero!<control::Point>()" end||I<-lists:seq(0,N-1)]),"], domains: [",
     lists:join(",",[["control::Domain { valid:true,mask:bits[axis::FRAME_BITS]:0x",integer_to_list(M,16),
         ",value:bits[axis::FRAME_BITS]:0x",integer_to_list(V,16)," }"]||#{mask:=M,value:=V}<-Domains]++
         lists:duplicate(D-length(Domains),"zero!<control::Domain>()")),"] },\n"].

%% Checked plan integers alone enter the constant declarations.
-spec n(non_neg_integer()) -> string().
n(I) -> integer_to_list(I).
