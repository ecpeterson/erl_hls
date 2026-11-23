-module(xls_template).
-moduledoc "Fills explicit slots in installed DSLX templates for actor and topology renderers. Rejects missing, repeated or unresolved slots before source emission; typed planning and DSLX validation remain outside this text-composition helper.".

%% Checked template composition.
-export([render/2]).

-doc "Substitutes every declared marker exactly once; malformed templates fail generation.".
-spec render(binary(), [{binary(), iodata()}]) -> binary().
render(Template, Bindings) ->
    Result = lists:foldl(fun replace/2, Template, Bindings),
    case re:run(Result, <<"@@[A-Z_]+@@">>, [{capture, first, binary}]) of
        nomatch -> Result;
        {match, [Marker]} -> error({unresolved_template_slot, Marker})
    end.

%% A marker is an explicit interface, never a substring of generated program text.
-spec replace({binary(), iodata()}, binary()) -> binary().
replace({Marker, Text}, Template) ->
    case binary:matches(Template, Marker) of
        [_] -> binary:replace(Template, Marker, iolist_to_binary(Text));
        Matches -> error({template_slot_count, Marker, length(Matches)})
    end.
