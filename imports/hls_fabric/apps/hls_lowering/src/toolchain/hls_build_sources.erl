-module(hls_build_sources).
-moduledoc """
In-memory Erlang source loading shared by hls_scheduler_build and hls_protocol_transport. Invokes the ordinary compiler and parse transforms, preserves hls_source context, and reports structured hls_diagnostic failures. It does not select a topology, placement or hardware schedule.
""".
%% Declared source loading.
-export([load/2]).

-doc "Compiles and loads one declared source without writing BEAM files. Captures compiler errors and warnings as structured diagnostics; parse-transform exceptions retain their original stack. Compiler options preserve source-context metadata for subsequent hardware lowering.".
-spec load(file:filename(), [hls_source:compiler_option()]) -> module().
load(File, Options) ->
    Quiet = [
        Option
     || Option <- Options,
        not lists:member(Option, [report, report_errors, report_warnings, verbose])
    ],
    hls_diagnostic:with_context(#{source => unicode:characters_to_binary(File)}, fun() ->
        case
            compile:file(File, [
                binary, debug_info, warnings_as_errors, return_errors, return_warnings | Quiet
            ])
        of
            {ok, Module, Bytes, []} ->
                {module, Module} = code:load_binary(Module, File, Bytes),
                Module;
            {error, Errors, Warnings} ->
                compile_failure(Errors, Warnings)
        end
    end).

%% Compiler returns source/formatter triples; parse-transform exceptions retain their real stack.
-type compiler_messages() :: [{file:filename(), [{erl_anno:location() | none, module(), term()}]}].

%% Ordinary syntax and warning failures are expected input errors, unlike transform crashes.
-spec compile_failure(compiler_messages(), compiler_messages()) -> no_return().
compile_failure(Errors, Warnings) ->
    lists:foreach(
        fun({_File, Messages}) ->
            lists:foreach(
                fun
                    (
                        {_Location, compile, {parse_transform, _Transform, {Class, Reason, Stack}}}
                    ) when
                        Class =:= error; Class =:= exit; Class =:= throw
                    ->
                        erlang:raise(Class, Reason, Stack);
                    (_) ->
                        ok
                end,
                Messages
            )
        end,
        Errors
    ),
    hls_diagnostic:raise(
        source,
        source_compile_failed,
        <<"Source compilation failed; fix the reported errors or warnings.">>,
        #{errors => compiler_messages(Errors), warnings => compiler_messages(Warnings)}
    ).

%% Preserve formatter ownership and raw reasons alongside their ordinary human explanation.
-spec compiler_messages(compiler_messages()) -> [map()].
compiler_messages(Groups) ->
    [
        #{
            source => unicode:characters_to_binary(File),
            location => Location,
            module => Formatter,
            reason => Reason,
            message => unicode:characters_to_binary(Formatter:format_error(Reason))
        }
     || {File, Messages} <- Groups, {Location, Formatter, Reason} <- Messages
    ].
