-module(hls_actor_source).
-moduledoc "Actor state and message declarations from preprocessed source. Source order determines wire tags; these queries do not lower callback bodies or emit hardware.".
-export([state/1, tags/1, message_words/2]).

%% The u8 wire tag reserves none, error and actor data before public messages.
-define(MAX_PUBLIC_TAGS, 253).

-doc "Returns the hls_data record name, or infers it from init/1's record return type.".
-spec state([hls_source:form()]) -> atom().
state(Forms) ->
    case hls_source:find_optional_attribute(Forms, hls_data) of
        {ok, Name} -> Name;
        none -> inferred_state(Forms)
    end.

%% Only the legacy direct record return type supplies an implicit actor data name.
-spec inferred_state([hls_source:form()]) -> atom().
inferred_state(Forms) ->
    {attribute, _, spec, {{init, 1}, [{type, _, 'fun', [_,
        {type, _, record, [{atom, _, Name}]}]}]}} = hls_source:find_spec(Forms, init, 1),
    Name.

-doc "Concatenates hls_tags blocks in source order. Rejects missing declarations, non-atom entries, duplicates and more than 253 public tags.".
-spec tags([hls_source:form()]) -> [atom()].
tags(Forms) ->
    Fragments = [{Line, Value} || {attribute, Line, hls_tags, Value} <- Forms],
    case Fragments of
        [] -> error({missing_hls_attribute, hls_tags});
        _ ->
            Tags = lists:append([validate_tag_fragment(Line, Value)
                || {Line, Value} <- Fragments]),
            case duplicate_tags(Tags, #{}, []) of
                [] -> validate_tag_count(Tags);
                Duplicates -> error({duplicate_hls_tags, Duplicates})
            end
    end.

%% Bound the wire vocabulary after validating values and duplicate order.
-spec validate_tag_count([atom()]) -> [atom()].
validate_tag_count(Tags) when length(Tags) =< ?MAX_PUBLIC_TAGS -> Tags;
validate_tag_count(Tags) -> error({too_many_hls_tags, length(Tags), ?MAX_PUBLIC_TAGS}).

%% Report the declaration's source location rather than losing it during concatenation.
-spec validate_tag_fragment(erl_anno:anno(), term()) -> [atom()].
validate_tag_fragment(Line, Tags) when is_list(Tags) ->
    case lists:all(fun is_atom/1, Tags) of
        true -> Tags;
        false -> error({invalid_hls_tags, Line, Tags})
    end;
validate_tag_fragment(Line, Value) -> error({invalid_hls_tags, Line, Value}).

%% Keep each duplicate once, in the order in which its second occurrence appeared.
-spec duplicate_tags([atom()], #{atom() => non_neg_integer()}, [atom()]) -> [atom()].
duplicate_tags([], _Counts, Duplicates) -> lists:reverse(Duplicates);
duplicate_tags([Tag | Rest], Counts, Duplicates) ->
    Count = maps:get(Tag, Counts, 0),
    Next = case Count of 1 -> [Tag | Duplicates]; _ -> Duplicates end,
    duplicate_tags(Rest, Counts#{Tag => Count + 1}, Next).

-doc "Returns a record's 32-bit transport word count, including provider padding. Rejects payloads exceeding the current 96-bit actor message limit.".
-spec message_words([hls_source:form()], atom()) -> 0..3.
message_words(Forms, Name) ->
    Record = hls_records:find(Forms, Name),
    Width = hls_records:width(Record),
    case Width =< 96 of
        true -> (Width + 31) div 32;
        false -> hls_diagnostic:raise(actor_source, message_too_wide,
            <<"Actor message exceeds the 96-bit transport payload limit">>,
            (record_context(Forms, Name, #{}))#{record => Name, width => Width, max_width => 96})
    end.

%% File attributes track include entry/return, so the record points to its actual declaration.
-spec record_context([hls_source:form()], atom(), hls_diagnostic:context()) -> hls_diagnostic:context().
record_context([{attribute, _, file, {File, _}} | Rest], Name, Context) ->
    record_context(Rest, Name, Context#{source => unicode:characters_to_binary(File)});
record_context([{attribute, Anno, record, {Name, _}} | _], Name, Context) ->
    Context#{location => erl_anno:location(Anno)};
record_context([_ | Rest], Name, Context) -> record_context(Rest, Name, Context).
