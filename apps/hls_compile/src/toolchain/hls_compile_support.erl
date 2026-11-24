-module(hls_compile_support).
-moduledoc """
Resolves and configures the installed computation-synthesis support tree.

The returned layout contains compiler DSLX and caller-owned imports only. Fabric and target
support are added by their owning bundle orchestrator. Configuration mutates a fresh bundle
copy before publication; it never changes the installed application.
""".

-export([layout/1, configure/2]).
-export_type([layout/0, library/0]).

-doc "One installed or caller-owned source tree, its bundle destination and retained suffixes.".
-type library() :: {file:filename(), file:filename(), [string()]}.

-doc "Compiler support trees and their bundle-relative import directories.".
-type layout() :: #{libraries := [library()], imports := [binary()]}.

-doc "Returns compiler and caller-owned support trees without writing files. Every caller import must exist.".
-spec layout([file:filename()]) -> layout().
layout(Imports) ->
    Priv = code:priv_dir(hls_compile),
    Extra = [
        {filename:absname(Source), "support/import" ++ integer_to_list(I), [".x"]}
     || {I, Source} <- lists:enumerate(0, Imports)
    ],
    Libraries = [{filename:join(Priv, "xls"), "support/compiler/xls", [".x"]} | Extra],
    lists:foreach(fun({Source, _, _}) -> {ok, _} = file:list_dir(Source) end, Libraries),
    Candidates =
        [{filename:join([Priv, "xls", "lib"]), "support/compiler/xls/lib"}] ++
            [{Source, Target} || {Source, Target, _} <- Extra],
    #{
        libraries => Libraries,
        imports => [
            unicode:characters_to_binary(Target)
         || {Source, Target} <- Candidates, filelib:is_dir(Source)
        ]
    }.

-doc "Writes one checked ordinary-frame layout into an unpublished compiler support snapshot.".
-spec configure(file:filename(), hls_frame_layout:layout()) -> ok.
configure(Output, Layout) ->
    case filelib:is_file(filename:join(Output, "source-build.json")) of
        true -> error({published_bundle, Output});
        false -> ok
    end,
    Path = filename:join([Output, "support", "compiler", "xls", "lib", "frame_config.x"]),
    {ok, _} = file:read_file_info(Path),
    ok = file:write_file(Path, xls_frame_layout:config(Layout)).
