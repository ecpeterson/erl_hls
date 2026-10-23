-module(hls_protocol_network_tests).
-moduledoc "Public network boundary rejects unsupported activation before source or filesystem work.".
-include_lib("eunit/include/eunit.hrl").

%% An invalid mode cannot be silently interpreted as automatic activation.
-spec unsupported_activation_test() -> ok.
unsupported_activation_test() ->
    ?assertError({unsupported_protocol_activation,pause},
        hls_protocol_network:write(#{activation=>pause},"unused")),
    ?assertError({unsupported_protocol_activation,<<"explicit_start">>},
        hls_protocol_network:write(#{activation=><<"explicit_start">>},"unused")).
