-module(hls_phi_profile_debug).
-moduledoc "Repeated public topology queries for the service-capacity experiment; samples are not simultaneous.".
-export([open/1, initial/1, reply/3, save/1]).

-doc "Loads per-device manifests and an explicit bounded sampling plan; an empty plan disables queries.".
-spec open(file:filename()) -> map().
open(Stage) ->
    {ok, Bytes} = file:read_file(filename:join(Stage, "probes.json")),
    Plan = json:decode(Bytes),
    {ok, [#{devices := ApplicationDevices}]} = file:consult(filename:join(Stage, "deployment.term")),
    Offset = length(ApplicationDevices),
    Devices = maps:from_list([begin
        {ok, Data} = file:read_file(filename:join(Stage, "device" ++ integer_to_list(D) ++ "-manifest.json")),
        Manifest = #{<<"fingerprint">> := Fingerprint, <<"resources">> := Resources} = json:decode(Data),
        Fingerprint = hls_topology_debug:manifest_fingerprint(Manifest),
        IDs = maps:get(integer_to_binary(D), Plan),
        {D+Offset, #{manifest => Manifest, resources => list_to_tuple(Resources), ids => IDs,
            cursor => 0, pending => info, samples => []}}
    end || D <- ApplicationDevices, maps:is_key(integer_to_binary(D), Plan)]),
    #{stage => Stage, devices => Devices, offset => Offset}.

-doc "Requests the immutable identity of each sampled device before any occupancy query.".
-spec initial(map()) -> [tuple()].
initial(#{devices := Devices}) ->
    [request(D, 16#10, <<>>) || {D, #{ids := [_ | _]}} <- lists:sort(maps:to_list(Devices))].

-doc "Validates a public reply and schedules the next resource, retaining its hardware capture cycle.".
-spec reply(non_neg_integer(), [non_neg_integer()], map()) -> {map(), [tuple()]}.
reply(D, [16#20001, Header | Words], State = #{devices := Devices}) ->
    Device = #{pending := Pending, samples := Samples} = maps:get(D, Devices),
    <<Op:8, 0:8, 0:8, Size:8>> = <<Header:32>>,
    Size = length(Words),
    Payload = << <<W:32/little>> || W <- Words >>,
    Updated = case Pending of
        info ->
            %% Verify the same manifest that supplies resource identity and decoding.
            16#90 = Op,
            {ok, #{fingerprint := Hash, resources := Count}} = hls_topology_debug:decode_info(Payload),
            #{manifest := #{<<"fingerprint">> := Hash}, resources := Resources} = Device,
            Count = tuple_size(Resources),
            Device;
        Id ->
            16#91 = Op,
            {ok, Sample} = hls_shared_observation:decode_observation(Payload, element(Id+1, maps:get(resources, Device))),
            Device#{samples := [Sample | Samples]}
    end,
    #{ids := IDs, cursor := Cursor} = Updated,
    NextId = lists:nth(Cursor+1, IDs),
    Next = Updated#{cursor := (Cursor+1) rem length(IDs), pending := NextId},
    {State#{devices := Devices#{D := Next}}, [request(D, 16#11, <<NextId:32/little>>)]}.

-doc "Writes every decoded observation and selected resource identity for reproducible timeline rendering.".
-spec save(map()) -> ok.
save(#{stage := Stage, devices := Devices, offset := Offset}) ->
    Reports = [begin
        #{manifest := #{<<"fingerprint">> := Fingerprint}, resources := Resources, ids := IDs, samples := Samples} = Device,
        true = lists:sort(IDs) =:= lists:usort([Id || #{id := Id} <- Samples]),
        #{device => D-Offset, fingerprint => Fingerprint,
            resources => [element(Id+1, Resources) || Id <- IDs], samples => [json_sample(S) || S <- lists:reverse(Samples)]}
    end || {D, Device} <- lists:sort(maps:to_list(Devices))],
    hls_bridge_phi_live:save(Stage, "occupancy.json", Reports).

%% Endpoint 2 is the public topology service; host endpoint 1 owns this test-only transaction.
-spec request(non_neg_integer(), byte(), binary()) -> tuple().
request(D, Op, Payload) -> {D, {1, 2}, {Op, 0, 0}, Payload}.

%% Preserve the public reduction population without relying on a JSON tuple extension.
-spec json_sample(map()) -> map().
json_sample(Sample = #{reduction := Reduction = #{population := {Mode, Members}}}) ->
    Sample#{reduction := Reduction#{population := #{mode => Mode, value => Members}}};
json_sample(Sample) -> Sample.
