-module(hls_source_dslx).
-export([write/1]).

write(Stage) ->
    {ok, Semantics} = file:read_file("test_data/hls_source_context_semantics.inc.x"),
    hls_source_fixture:with_source(fun(Path, Directory) ->
        lists:foreach(fun({Name, Macros}) ->
            Options = hls_source_fixture:options(Directory) ++ Macros,
            hls_source_fixture:compile_actor(Path, Options),
            Interface = hls_actor_interface:from_module(hls_source_context_fixture),
            #{width := Width} = hls_actor_interface:state(Interface),
            #{mailbox_capacity := Capacity} = Interface,
            {ok, waiting, Cell} = hls_source_context_fixture:init([]),
            <<Initial:Width/little>> = hls_source_context_fixture:pack(Cell),
            Values = lists:usort([0, 1, 255, 65535, (1 bsl Width) - 1,
                1 bsl (Width - 1), (1 bsl (Width - 1)) - 1]),
            Expected = [begin
                {waiting, Updated, consume} = hls_source_context_fixture:waiting(
                    cast, {message, Value}, Cell),
                <<Packed:Width/little>> = hls_source_context_fixture:pack(Updated),
                Packed
            end || Value <- Values],
            ok = file:write_file(filename:join(Stage, Name ++ ".x"), [
                xls_parse:to_xls(Path, #{source_options => Options}),
                io_lib:format("\ntype Word = u~B;\nconst EXPECTED_CAPACITY = u8:~B;\n"
                    "const EXPECTED_INITIAL = u64:~B;\n", [Width, Capacity, Initial]),
                array("INPUTS", Values), array("EXPECTED", Expected), Semantics
            ])
        end, [{"source_narrow", [{d, 'CAPACITY', 2}]},
              {"source_wide", [{d, 'CAPACITY', 5}, {d, 'WIDE'}]}])
    end).

array(Name, Values) ->
    ["const ", Name, " = u64[", integer_to_list(length(Values)), "]:[",
        lists:join(", ", [integer_to_list(V) || V <- Values]), "];\n"].
