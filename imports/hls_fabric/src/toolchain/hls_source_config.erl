-module(hls_source_config).
-moduledoc "Reads one trusted Erlang source-build configuration without changing path resolution.".
-export([read/1]).

-doc "Consults exactly one map from a trusted Erlang terms file. Source and include paths remain relative to the caller's working directory; this function neither changes directory nor evaluates constructors.".
-spec read(file:filename()) -> map().
read(Filename) ->
    case file:consult(Filename) of
        {ok, [Config]} when is_map(Config) -> Config;
        {ok, _} -> error({invalid_source_config, Filename});
        {error, Reason} -> error({source_config, Filename, Reason})
    end.
