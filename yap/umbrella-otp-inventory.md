# Umbrella source inventory

Stages 0–1 source inventory for the mechanical import. The detailed tables preserve the original audited feature-branch snapshot of 330 modules across eight applications. The selected-mainline overlay reconciles that evidence with the 390 modules across nine applications now landed in the umbrella; the recorded Stage 1 paths are the final paths. Source directories identify current responsibilities. Exports list explicit attributes. Call candidates include remote types and approximate text matches. Compile/resource candidates can miss macro expansion, computed paths and dynamic targets.

## Audited feature snapshot

| Repository | Commit |
| --- | --- |
| erl_hls | a9198df1705a8eb313d20e78871ed53225488f15 |
| hls_fabric | 131bd191d39011253e6b86e496c86f1080dfc678 |
| hls_spacetime | efee619df1b37c3e11e0496d2eabc4231ce84623 |

Duplicate literal module names: —.

## Selected-mainline and landed overlay

| Repository | Selected revision | Modules |
| --- | --- | ---: |
| erl_hls | `b86502cc0149731409d878f9aec6c5264ae3f2eb` | 151 |
| hls_fabric | `4481afbde5a4ab1594141d698c74e0859ef8c72c` | 229 |
| hls_spacetime | `3597ecf93ea789c745bc3014ea2c4de8cd5fb243` | 10 |

The selected and landed set has 390 literal module identities and no duplicates. Application ownership remains mechanical:

| Application | Selected modules | Change from snapshot |
| --- | ---: | ---: |
| erl_hls | 102 | +9 |
| hls_runtime | 49 | +13, −1 |
| hls_fabric | 49 | +16 |
| hls_lowering | 122 | +16, −3 |
| hls_phi | 38 | +1 |
| hls_snowflake | 9 | — |
| hls_spacetime_observer | 9 | Seven additions; the two existing observer modules retain their identities under the renamed application. |
| router | 2 | New standalone application identity |
| hls_spacetime | 10 | — |

Added module identities, grouped by selected application:

- `erl_hls`: `hls_atom_types`, `hls_compile_topology`, `hls_server_source`, `xls_entry_comprehensions`, `xls_helper_modules`, `xls_provider_enum`, `xls_provider_ring`, `xls_source_helpers`, `xls_source_map`.
- `hls_runtime`: `hls_actor_callback`, `hls_admission`, `hls_domain`, `hls_domain_backend`, `hls_domain_erts`, `hls_domain_ids`, `hls_domain_instance`, `hls_domain_lifecycle`, `hls_domain_owner`, `hls_domain_store`, `hls_enum`, `hls_ring`, `hls_supervisor_lifecycle`.
- `hls_fabric`: `hls_domain_channel`, `hls_domain_channel_binding`, `hls_domain_channel_fabric`, `hls_domain_channel_instance`, `hls_domain_channel_rx`, `hls_domain_channel_tx`, `hls_domain_channel_wire`, `hls_domain_endpoint`, `hls_domain_endpoint_pair`, `hls_domain_endpoint_wire`, `hls_domain_fabric`, `hls_domain_wire`, `hls_node_domain`, `hls_node_requests`, `hls_supervisor_fabric`, `hls_supervisor_wire`.
- `hls_lowering`: `hls_domain_board_control`, `hls_domain_channel_build`, `hls_domain_channels_stream`, `hls_domain_endpoint_build`, `hls_domain_endpoint_network`, `hls_domain_endpoint_packets`, `hls_domain_endpoint_role`, `hls_domain_endpoints_stream`, `hls_domain_stream`, `hls_protocol_domain`, `hls_protocol_domains`, `hls_protocol_supervisor`, `hls_supervisor_stream`, `sv_domain_channels`, `sv_domain_supervisor`, `xls_clocked_controller`.
- `hls_phi`: `phi_direction`.
- `hls_spacetime_observer`: `xls_protocol_spacetime_ancestry`, `xls_protocol_spacetime_cli`, `xls_protocol_spacetime_dependencies`, `xls_protocol_spacetime_physical`, `xls_protocol_spacetime_publication`, `xls_protocol_spacetime_stream`, `xls_protocol_spacetime_workflow`.
- `router`: `router`, `router_barrier`.

Removed module identities are `hls_gs_deferred`, `xls_gs_deferred`, `xls_gs_immediate` and `xls_gs_lower`. The two retained snapshot identities `xls_protocol_spacetime` and `xls_protocol_spacetime_capture` now belong to `hls_spacetime_observer`; their Stage 1 paths change only by that application-directory rename. All other detailed rows below retain their stated application disposition. New rows follow the same source-root-to-`apps/<app>` rules recorded in the [Stages 0–1 audit](umbrella-otp-audit.md).

## erl_hls modules

| Source / responsibility | Module | Current and Stage 1 app | Explicit exports | Candidate consumers | Compile declarations | Remote references | Resource or dispatch calls | Stage 1 path | BEAM imports |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| apps/hls_runtime/src/api/hls_bits.erl | hls_bits | hls_runtime | bits/1, padded/2 width/2, value_width/2, zero/2, pack/3, unpack/3 | packed_samples, xls_machine_layout, xls_provider_bits | behavior hls_type | hls_codec, hls_type | — | apps/hls_runtime/src/api/hls_bits.erl | erlang, hls_codec, hls_type |
| apps/hls_runtime/src/api/hls_bool.erl | hls_bool | hls_runtime | bool/0 width/2, value_width/2, zero/2, pack/3, unpack/3 | snowflake_coordinator, snowflake_vertex, telemetry_calibrator, xls_helpers, xls_provider_bool | behavior hls_type, compile no_auto_import_types | erlang, hls_type, values | — | apps/hls_runtime/src/api/hls_bool.erl | erlang |
| apps/hls_runtime/src/api/hls_continuation.erl | hls_continuation | hls_runtime | names/1, validate/1, require/2 | hls_callback_actions, hls_service_contract, hls_statem, xls_statem_continuation | — | lists, proplists | — | apps/hls_runtime/src/api/hls_continuation.erl | erlang, lists, proplists |
| apps/hls_runtime/src/api/hls_field_layout.erl | hls_field_layout | hls_runtime | layout/2 | hls_frame_layout, xls_frame_layout, xls_machine_layout, xls_protocol_envelope, xls_record_codegen, xls_statem_gather_layout, xls_struct_codec | — | hls_record, hls_type, lists | — | apps/hls_runtime/src/api/hls_field_layout.erl | erlang, hls_type, lists |
| apps/hls_runtime/src/api/hls_fixed.erl | hls_fixed | hls_runtime | signed/2, from_integer/2, from_ratio/3, to_float/2, saturate/2, round_ratio/2, wrap/2 width/2, zero/2, pack/3, unpack/3 | phi_field, xls_provider_fixed | behavior hls_type | hls_codec, hls_type | — | apps/hls_runtime/src/api/hls_fixed.erl | erlang, hls_codec, hls_type |
| apps/hls_runtime/src/api/hls_float.erl | hls_float | hls_runtime | literal/2, add/3, sub/3, mul/3, eq/3, lt/3 format/1 | xls_provider_float, xls_provider_nums | — | binary, error, hls_type | — | apps/hls_runtime/src/api/hls_float.erl | binary, erlang, hls_type |
| apps/hls_runtime/src/api/hls_frame_layout.erl | hls_frame_layout | hls_runtime | new/1, default/0, payload_words/1, payload_bits/1, frame_bits/1, word_bits/0, header_bits/0, header_fields/0, header_offset/1, descriptor/1, bounds/4 check_payload/2, pack_header/1, unpack_header/1, pack/3, unpack/2, pack_integer/3, unpack_integer/2 | hls_actor_interface, hls_actor_source, hls_build_profile, hls_compile, hls_fabric_io, hls_local_actor, hls_partition, hls_partition_ingress, hls_partition_reduction, hls_partition_schedule, hls_partition_shared_dslx, hls_partition_tile, hls_partition_tile_debug, hls_protocol_application_binding, hls_protocol_application_codec, hls_protocol_application_schema, hls_protocol_bridge, hls_protocol_capture, hls_protocol_codec, hls_protocol_codec_plan, hls_protocol_control, hls_protocol_fabric, hls_protocol_inbox, hls_protocol_mixed_codec, hls_protocol_projection, hls_protocol_schema, hls_protocol_source, hls_protocol_transport, hls_scheduler_build, hls_scheduler_plan, hls_shared_debug_catalog, hls_source_build, hls_source_config, hls_topology_constants, phi_decoder_profile_build, phi_partition_ram, sv_protocol_application, telemetry, xls_actor_codegen, xls_actor_program, xls_fabric_topology_dslx, xls_fabric_topology_instance_dslx, xls_fabric_topology_profile, xls_frame_layout, xls_gs_deferred, xls_gs_immediate, xls_gs_lower, xls_message_bits, xls_message_facts, xls_parse, xls_partition_application, xls_phase_specialize, xls_phase_values, xls_protocol_boundary, xls_protocol_bridge, xls_protocol_codec, xls_protocol_inbox, xls_protocol_network, xls_protocol_partition, xls_publication_codegen, xls_scheduler_actor, xls_scheduler_debug, xls_scheduler_ram_v, xls_statem_lower, xls_statem_plan, xls_topology_family_dslx, xls_topology_graph, xls_topology_profile | — | hls_codec, hls_diagnostic, hls_field_layout, hls_nums, hls_record, hls_type, xls_frame_layout | — | apps/hls_runtime/src/api/hls_frame_layout.erl | erlang, hls_codec, hls_diagnostic, hls_field_layout, hls_nums, hls_type |
| apps/hls_runtime/src/api/hls_gs.erl | hls_gs | hls_runtime | start_link/2, start_link/3, stop/1 init/1, handle_call/3, handle_cast/2, handle_continue/2, handle_info/2, terminate/2, code_change/3 from/0, width/2, zero/2, pack/3, unpack/3 generic_unpack/2, encode_request/3, decode_reply/3 | hls_node_connection, hls_statem, regsvc | behavior gen_server | gen_server, hls_codec, hls_fabric_client, hls_gs_deferred, hls_nums, hls_service_schema, hls_type, lists, maps, result | — | apps/hls_runtime/src/api/hls_gs.erl | erlang, gen_server, hls_codec, hls_fabric_client, hls_gs_deferred, hls_nums, hls_service_schema, hls_type, lists |
| apps/hls_runtime/src/api/hls_lists.erl | hls_lists | hls_runtime | list/2, new/2, sublist/4, nth/2, set/3, array_slice/4 zero/2, pack/3, unpack/3, width/2, value_width/2 | hls_lists, hls_vec, regsvc, snowflake_vertex, xls_provider_lists | behavior hls_type | hls_codec, hls_lists, hls_type, lists | — | apps/hls_runtime/src/api/hls_lists.erl | erlang, hls_codec, hls_type, lists |
| apps/hls_runtime/src/api/hls_nums.erl | hls_nums | hls_runtime | u8/0, s8/0, u16/0, s16/0, u32/0, s32/0, u64/0, s64/0, uN/1, sN/1, float64/0, float32/0, float16/0, wrap/2 signedness/1 width/2, zero/2, pack/3, unpack/3, value_width/2 | hls_actor_source, hls_counter_example, hls_fabric_io, hls_frame_layout, hls_gs, hls_prng, hls_protocol_envelope, packed_samples, phi_field, phi_memory_cpu_fabric, phi_memory_demo, phi_memory_experiment, phi_noise_topology, phi_noise_topology_dslx, phi_repetition_memory, phi_repetition_topology, phi_shared_noise_topology_dslx, phi_syndrome_replay_cell, phi_torus_topology, regsvc, snowflake_barrier, snowflake_coordinator, snowflake_vertex, telemetry_calibrator, telemetry_window, xls_actor_codegen, xls_machine_layout, xls_message_bits, xls_named_bits, xls_provider_nums, xls_statem_gather_layout | behavior hls_type | hls_codec, hls_type | — | apps/hls_runtime/src/api/hls_nums.erl | erlang, hls_codec |
| apps/hls_runtime/src/api/hls_prng.erl | hls_prng | hls_runtime | xorshift32/1 | phenom_data_cell, phi_syndrome_replay_cell | — | hls_nums | — | apps/hls_runtime/src/api/hls_prng.erl | erlang |
| apps/hls_runtime/src/api/hls_record.erl | hls_record | hls_runtime | zero/2, width/2, value_width/2, pack/3, unpack/3 | hls_field_layout, hls_frame_layout, hls_protocol_envelope, hls_record_codec, hls_records, xls_provider_record | — | hls_type, lists | — | apps/hls_runtime/src/api/hls_record.erl | erlang, hls_type, lists |
| apps/hls_runtime/src/api/hls_record_codec.erl | hls_record_codec | hls_runtime | bind/2, width/1, check/1 pack/2, unpack/2 | hls_host_codec, hls_host_codec_plan, hls_node_binding, hls_partition_ingress, hls_partition_wire, hls_protocol_mixed_codec, hls_protocol_mixed_host, hls_protocol_mixed_schema | — | code, erlang, hls_codec, hls_record, hls_type, lists, proof | code:ensure_loaded | apps/hls_runtime/src/api/hls_record_codec.erl | code, erlang, hls_codec, hls_record, hls_type, lists |
| apps/hls_runtime/src/api/hls_serial.erl | hls_serial | hls_runtime | counter/1, wrap/2, add/3, difference/3, before/3 width/2, zero/2, pack/3, unpack/3 | snowflake_barrier, snowflake_coordinator, snowflake_vertex, xls_provider_serial | behavior hls_type | explicitly, hls_codec, hls_type | — | apps/hls_runtime/src/api/hls_serial.erl | erlang, hls_codec |
| apps/hls_runtime/src/api/hls_service_schema.erl | hls_service_schema | hls_runtime | from_module/1 | hls_gs, hls_gs_deferred, hls_node, hls_service_contract, hls_statem | — | proplists | — | apps/hls_runtime/src/api/hls_service_schema.erl | erlang, proplists |
| apps/hls_runtime/src/api/hls_statem.erl | hls_statem | hls_runtime | start_link/3, connect/2, stop/1, cast/2, call/2, call/3, info/1, info/2 init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3 | hls_counter_example, hls_debug_target, hls_protocol_mixed_admission, hls_protocol_mixed_stream, phi_memory_cpu_fabric, phi_syndrome_replay_cell, snowflake_actor_run, snowflake_barrier, snowflake_coordinator, snowflake_vertex, telemetry, telemetry_calibrator, telemetry_window | behavior gen_server | erlang, gen_server, hls_callback_actions, hls_continuation, hls_gs, hls_indexed_gather, hls_mailbox, hls_reduction, hls_reply_book, hls_service_schema, lists, maps, proplists, sys | — | apps/hls_runtime/src/api/hls_statem.erl | erlang, gen_server, hls_callback_actions, hls_continuation, hls_indexed_gather, hls_mailbox, hls_reduction, hls_reply_book, hls_service_schema, lists, maps, proplists, sys |
| apps/hls_runtime/src/api/hls_type.erl | hls_type | hls_runtime | zero/0, zero/1, as/2 descriptor/1, providers/1, width/1, value_width/1, normalize/2, pack/2, pack_exact/2, unpack/2 | hls_actor_constants, hls_actor_interface, hls_bits, hls_bool, hls_counter_example, hls_field_layout, hls_fixed, hls_float, hls_frame_layout, hls_gs, hls_lists, hls_node_topology, hls_nums, hls_pack, hls_partition, hls_protocol_capture, hls_protocol_codec_plan, hls_protocol_envelope, hls_protocol_projection, hls_protocol_schema, hls_protocol_transactions, hls_record, hls_record_codec, hls_records, hls_serial, hls_topology_constants, hls_vec, packed_samples, phi_field, phi_syndrome_replay_cell, regsvc, snowflake_barrier, snowflake_coordinator, snowflake_vertex, telemetry_calibrator, telemetry_window, xls_clause_lower, xls_entry_storage, xls_helpers, xls_known_bits, xls_literal_types, xls_machine_layout, xls_message_bits, xls_message_facts, xls_named_bits, xls_provider_bits, xls_provider_bool, xls_provider_fixed, xls_provider_float, xls_provider_lists, xls_provider_nums, xls_provider_serial, xls_provider_vec, xls_publication_codegen, xls_state_projection, xls_statem_lower, xls_statem_reduction_ir, xls_statem_reduction_lower, xls_topology_ingress, xls_topology_scheduler_plan, xls_type | — | code, erl_parse, erlang, hls_codec, lists | code:ensure_loaded | apps/hls_runtime/src/api/hls_type.erl | code, erlang, hls_codec, lists |
| apps/hls_runtime/src/api/hls_vec.erl | hls_vec | hls_runtime | vector/2, nth/2, set/3, dot/3 width/2, zero/2, pack/3, unpack/3, value_width/2 | phi_field, xls_provider_vec | behavior hls_type | hls_lists, hls_type | — | apps/hls_runtime/src/api/hls_vec.erl | erlang, hls_lists, hls_type |
| apps/hls_runtime/src/runtime/hls_actor_identity.erl | hls_actor_identity | hls_runtime | actor_key/1 | hls_debug_catalog, hls_partition_tile, hls_protocol_inspection, hls_protocol_observation, xls_actor_debug, xls_scheduler_debug | — | binary, crypto, string | — | apps/hls_runtime/src/runtime/hls_actor_identity.erl | binary, crypto, erlang, string |
| apps/hls_runtime/src/runtime/hls_callback_actions.erl | hls_callback_actions | hls_runtime | split/3 | hls_gs_deferred, hls_statem | — | hls_continuation | — | apps/hls_runtime/src/runtime/hls_callback_actions.erl | erlang, hls_continuation |
| apps/hls_runtime/src/runtime/hls_codec.erl | hls_codec | hls_runtime | checked_integer/3, pack_integer/3, wrap_integer/3, pack_float/2, unpack_float16/1, unsigned/1, stream_bit_index/2 join/1, split/2, pad_to/2, align/2 | hls_bits, hls_fixed, hls_frame_layout, hls_gs, hls_lists, hls_node_binding, hls_nums, hls_partition, hls_partition_ingress, hls_partition_wire, hls_protocol_codec_plan, hls_protocol_mixed_host, hls_protocol_projection, hls_record_codec, hls_serial, hls_type, snowflake_actor_run, xls_nums, xls_topology_family_dslx, xls_topology_graph, xls_topology_scheduler_plan | — | — | — | apps/hls_runtime/src/runtime/hls_codec.erl | erlang |
| apps/hls_runtime/src/runtime/hls_debug.erl | hls_debug | hls_runtime | start_link/2, stop/1, query/4 encode_request/2, response/3 info/2, info/3, inspect_waits/2 get_counters/1, get_counters/2, get_trace/1, get_trace/2 init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2 | hls_debug_target, hls_node_connection, hls_process_profile, hls_protocol_observation, hls_topology_debug, snowflake_actor_run | behavior gen_server | gen_server, hls_debug_target, hls_fabric_client, lists | — | apps/hls_runtime/src/runtime/hls_debug.erl | erlang, gen_server, hls_debug_target, hls_fabric_client, lists |
| apps/hls_runtime/src/runtime/hls_debug_catalog.erl | hls_debug_catalog | hls_runtime | cpu/2, hardware/3, bind/3 actors/1, actor/2, boundaries/1 | hls_process_profile, hls_shared_debug_catalog, hls_shared_observation, phi_memory_cpu_fabric, xls_actor_debug | — | hls_actor_identity, hls_debug_target, lists, maps, xls_actor_debug | — | apps/hls_runtime/src/runtime/hls_debug_catalog.erl | erlang, hls_actor_identity, lists, maps |
| apps/hls_runtime/src/runtime/hls_debug_target.erl | hls_debug_target | hls_runtime | info/3, collect/3, inspect_waits/2 | hls_debug, hls_debug_catalog | — | erlang, hls_debug, hls_statem, hls_topology_debug, lists, maps | — | apps/hls_runtime/src/runtime/hls_debug_target.erl | erlang, hls_debug, hls_statem, hls_topology_debug, lists, maps |
| apps/hls_runtime/src/runtime/hls_diagnostic.erl | hls_diagnostic | hls_runtime | raise/4, with_context/2 format/1, json/1, json_value/1 | hls_actor_source, hls_build, hls_build_profile, hls_build_sources, hls_cli, hls_compile, hls_compile_cli, hls_fabric_cli, hls_frame_layout, hls_local_actor, hls_protocol_application, hls_protocol_arithmetic, hls_protocol_bridge, hls_protocol_control, hls_protocol_deployment, hls_protocol_mixed, hls_protocol_model, hls_protocol_network, hls_protocol_partition, hls_protocol_schema, hls_protocol_topology, hls_protocol_transport, hls_scheduler_build, hls_source, hls_source_build, hls_source_config, phi_decoder_profile_build, xls_partition_application | — | binary, erlang, io_lib, json, lists, maps, unicode | — | apps/hls_runtime/src/runtime/hls_diagnostic.erl | binary, erlang, io_lib, json, lists, maps, unicode |
| apps/hls_runtime/src/runtime/hls_fabric.erl | hls_fabric | hls_runtime | start_link/2, start_link/3, stop/1, close/2, await_closed/2, open_session/1, drain_session/2 register_route/3, send/4, send/5, send_request/5, ack/2, info/1, client_info/1 init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2 | hls_dma_device, hls_fabric_client, hls_node, hls_node_connection, hls_partition_stream, hls_partition_wire, hls_protocol_bridge_wire, hls_protocol_mixed_stream, hls_protocol_stream, phi_memory_runner | behavior gen_server | erlang, gen_server, hls_fabric_io, hls_fabric_lease, hls_fabric_session, lists, maps, queue | — | apps/hls_runtime/src/runtime/hls_fabric.erl | erlang, gen_server, hls_fabric_io, hls_fabric_lease, hls_fabric_session, lists, maps, queue |
| apps/hls_runtime/src/runtime/hls_fabric_client.erl | hls_fabric_client | hls_runtime | new/4, request/5, cast/4 receive_frame/6, handle_info/2, info/1 | hls_debug, hls_gs | — | gen_server, hls_fabric, maps | — | apps/hls_runtime/src/runtime/hls_fabric_client.erl | erlang, gen_server, hls_fabric, maps |
| apps/hls_runtime/src/runtime/hls_fabric_io.erl | hls_fabric_io | hls_runtime | run/4 encode/3, valid_route/1 | hls_fabric, hls_fabric_lease | — | file, hls_fabric_lease, hls_frame_layout, hls_nums | file:close, file:io_device, file:open, file:read, file:write | apps/hls_runtime/src/runtime/hls_fabric_io.erl | erlang, file, hls_fabric_lease, hls_frame_layout |
| apps/hls_runtime/src/runtime/hls_fabric_lease.erl | hls_fabric_lease | hls_runtime | open/3, closed/2, await/2 init/1, handle_call/3, handle_cast/2, handle_info/2 | hls_fabric, hls_fabric_io | behavior gen_server, include_lib "kernel/include/file.hrl" | erlang, file, filename, gen_server, hls_fabric_io, lists, maps, persistent_term | file:read_file_info | apps/hls_runtime/src/runtime/hls_fabric_lease.erl | erlang, file, filename, gen_server, hls_fabric_io, lists, maps, persistent_term |
| apps/hls_runtime/src/runtime/hls_fabric_session.erl | hls_fabric_session | hls_runtime | start_link/1 init/1, handle_call/3, handle_cast/2, handle_info/2 | hls_fabric | behavior gen_server | gen_server | — | apps/hls_runtime/src/runtime/hls_fabric_session.erl | erlang, gen_server |
| apps/hls_runtime/src/runtime/hls_gs_deferred.erl | hls_gs_deferred | hls_runtime | new/1, dispatch/6 | hls_gs | — | hls_callback_actions, hls_reply_book, hls_service_schema | — | apps/hls_runtime/src/runtime/hls_gs_deferred.erl | erlang, hls_callback_actions, hls_reply_book |
| apps/hls_runtime/src/runtime/hls_indexed_gather.erl | hls_indexed_gather | hls_runtime | open/5, offer/5, info/1 | hls_statem | — | lists | — | apps/hls_runtime/src/runtime/hls_indexed_gather.erl | erlang, lists |
| apps/hls_runtime/src/runtime/hls_mailbox.erl | hls_mailbox | hls_runtime | new/1, new/2, reset/1 reserve/3, cancel/2, cancel_owner/2, commit/3 select/2, consume/2, info/1 | hls_statem | — | lists, maps, ordering | — | apps/hls_runtime/src/runtime/hls_mailbox.erl | erlang, lists, maps |
| apps/hls_runtime/src/runtime/hls_reduction.erl | hls_reduction | hls_runtime | open/4, contribute/5, contribute/6, info/1 | hls_statem | — | erlang, linear, lists, maps, value | — | apps/hls_runtime/src/runtime/hls_reduction.erl | erlang, lists, maps |
| apps/hls_runtime/src/runtime/hls_reply_book.erl | hls_reply_book | hls_runtime | new/1, admit/4, complete/2 | hls_gs_deferred, hls_statem | — | gen_server, lists, maps | — | apps/hls_runtime/src/runtime/hls_reply_book.erl | erlang, gen_server, lists, maps |
| apps/hls_runtime/src/runtime/hls_topology_debug.erl | hls_topology_debug | hls_runtime | open/2, info/1, query/2, query/3, resource/2, with_actor_observer/2 inspect_waits/3, write_wait_report/4 decode_info/1, decode_observation/2, decode_observation/3, actor_fields/1, mailbox_observation/2, manifest_fingerprint/1 | hls_debug_target, hls_protocol_inspection, hls_protocol_observation, hls_shared_observation | — | binary, code, crypto, erlang, file, hls_debug, hls_topology_wait, json, lists, maps, string | code:ensure_loaded, file:write_file | apps/hls_runtime/src/runtime/hls_topology_debug.erl | binary, code, crypto, erlang, file, hls_debug, hls_topology_wait, json, lists, maps, string |
| apps/hls_runtime/src/runtime/hls_topology_wait.erl | hls_topology_wait | hls_runtime | inspect_waits/4 | hls_topology_debug | — | digraph, digraph_utils, lists, maps | — | apps/hls_runtime/src/runtime/hls_topology_wait.erl | digraph, digraph_utils, erlang, lists, maps |
| src/backend/xls/actors/xls_actor_codegen.erl | xls_actor_codegen | erl_hls | artifact/3, emit/3 entry_expression/4, input_tag_ok/3, reply_failure_binding/1 | hls_protocol_source, xls_activation_codegen, xls_actor_program, xls_collection_codegen, xls_exclusive_collection_codegen, xls_gather_codegen, xls_indexed_collection_codegen, xls_local_owner, xls_machine_codegen, xls_message_facts, xls_parse, xls_phase_specialize, xls_phase_values, xls_scheduler_codegen, xls_statem_codegen, xls_statem_lower, xls_statem_plan | — | call_error, call_from, dispatched, enter_pending, failure, file, frame, hls_frame_layout, hls_nums, index, layout, lists, maps, next_event, payloads, phase_boundary, reply, reply_valid, xls_clause_lower, xls_dslx, xls_dslx_imports, xls_emitted, xls_entry_storage, xls_failure_sites, xls_frame_layout, xls_init, xls_names, xls_statem_event_codegen, xls_statem_gather_codegen, xls_statem_reduction_codegen, xls_statem_reduction_ir, xls_statem_reply_codegen | file:filename | apps/erl_hls/src/backend/xls/actors/xls_actor_codegen.erl | erlang, hls_frame_layout, lists, xls_dslx, xls_dslx_imports, xls_emitted, xls_entry_storage, xls_frame_layout, xls_init, xls_names, xls_statem_event_codegen, xls_statem_gather_codegen, xls_statem_reduction_codegen, xls_statem_reduction_ir, xls_statem_reduction_service_codegen, xls_statem_reply_codegen |
| src/backend/xls/actors/xls_actor_debug.erl | xls_actor_debug | erl_hls | projection/2, projection/3, validate/2 direct_bank/4, failures/1 catalog/3 | hls_debug_catalog, hls_protocol_inspection, xls_scheduler_debug | — | binary, crypto, hls_actor_identity, hls_actor_interface, hls_debug_catalog, hls_topology, io_lib, json, lists, maps, string, xls_actor_observation, xls_emitted, xls_failure_sites | — | apps/erl_hls/src/backend/xls/actors/xls_actor_debug.erl | binary, crypto, erlang, hls_actor_identity, hls_actor_interface, hls_debug_catalog, io_lib, json, lists, maps, string, xls_actor_observation, xls_emitted, xls_failure_sites |
| src/backend/xls/actors/xls_actor_observation.erl | xls_actor_observation | erl_hls | enabled/1, layout/1, collection/1, validate_channels/1 bindings/2, bindings/3, wires/1, ports/1, scalar_name/1, family_name/1, spawn_argument/2 imports/1, declarations/1, proc_field/1, config_parameter/1, config_value/1, sample/1 | hls_protocol_inspection, xls_actor_debug, xls_collection_observation, xls_direct_collection_codegen, xls_fabric_topology_instance_dslx, xls_fabric_topology_profile, xls_parse, xls_scheduler_actor, xls_scheduler_debug, xls_statem_codegen, xls_statem_lower, xls_topology_family_dslx, xls_topology_instance_dslx, xls_topology_profile | — | actor_debug_out, hls_actor_interface, hls_topology, lists, maps, xls_statem_reduction_ir | — | apps/erl_hls/src/backend/xls/actors/xls_actor_observation.erl | erlang, hls_actor_interface, lists, maps, xls_statem_reduction_ir |
| src/backend/xls/actors/xls_actor_program.erl | xls_actor_program | erl_hls | from_file/2, from_file/3 spec/1, plan/1, entry_effects/1 | hls_local_actor, hls_protocol_application_binding, hls_protocol_arithmetic, hls_protocol_capture, hls_protocol_identity, hls_protocol_inbox, hls_protocol_inspection, hls_protocol_inventory, hls_protocol_mixed, hls_protocol_partition, hls_protocol_schema, hls_protocol_source, hls_protocol_transactions, hls_protocol_transport | — | file, hls_frame_layout, hls_source, lists, xls_actor_codegen, xls_statem_plan | file:filename | apps/erl_hls/src/backend/xls/actors/xls_actor_program.erl | erlang, hls_frame_layout, lists, xls_statem_plan |
| src/backend/xls/actors/xls_callback_result.erl | xls_callback_result | erl_hls | map/2, map_actions/2 results/1 | xls_gs_deferred, xls_statem_entry, xls_statem_gather_lower, xls_statem_lower, xls_statem_reduction_lower | — | erl_parse, lists, maps | — | apps/erl_hls/src/backend/xls/actors/xls_callback_result.erl | erlang, lists, maps |
| src/backend/xls/actors/xls_entry_storage.erl | xls_entry_storage | erl_hls | identity/0, origin/2 plan/2, width/1 encode/2, decode/2 | hls_local_actor, xls_actor_codegen, xls_statem_entry, xls_statem_lower | — | frame, hls_records, hls_source, hls_type, lists, maps, xls_clause_lower, xls_dslx, xls_known_bits, xls_names, xls_type | — | apps/erl_hls/src/backend/xls/actors/xls_entry_storage.erl | erlang, hls_records, hls_type, lists, maps, xls_dslx, xls_known_bits, xls_names, xls_type |
| src/backend/xls/actors/xls_gs_deferred.erl | xls_gs_deferred | erl_hls | artifact/3, emit/2, emit/3 | xls_parse | — | erl_parse, error, file, from, hls_actor_source, hls_frame_layout, hls_records, hls_service_contract, hls_source, input, lists, maps, output, reply_allowed, state, tag, xls_callback_lower, xls_callback_result, xls_dslx, xls_dslx_imports, xls_emitted, xls_failure_sites, xls_frame_layout, xls_gs_lower, xls_hardware_source, xls_helpers, xls_names, xls_pattern_lower, xls_record_codegen | file:filename | apps/erl_hls/src/backend/xls/actors/xls_gs_deferred.erl | erlang, hls_actor_source, hls_frame_layout, hls_records, hls_service_contract, lists, maps, xls_callback_lower, xls_callback_result, xls_dslx_imports, xls_emitted, xls_failure_sites, xls_frame_layout, xls_gs_lower, xls_hardware_source, xls_helpers, xls_names, xls_pattern_lower, xls_record_codegen |
| src/backend/xls/actors/xls_gs_immediate.erl | xls_gs_immediate | erl_hls | artifact/3, emit/2, emit/3 | xls_parse | — | ext_recv, ext_send, file, header, hls_actor_source, hls_frame_layout, hls_records, hls_service_contract, hls_source, lists, req_in, resp_out, xls_dslx_imports, xls_emitted, xls_failure_sites, xls_frame_layout, xls_gs_lower, xls_hardware_source, xls_helpers, xls_names, xls_record_codegen | file:filename | apps/erl_hls/src/backend/xls/actors/xls_gs_immediate.erl | erlang, hls_actor_source, hls_frame_layout, hls_records, hls_service_contract, lists, xls_dslx_imports, xls_emitted, xls_failure_sites, xls_frame_layout, xls_gs_lower, xls_hardware_source, xls_helpers, xls_names, xls_record_codegen |
| src/backend/xls/actors/xls_gs_lower.erl | xls_gs_lower | erl_hls | initial_state/2 callback_arms/2, callback_arms/3 | xls_gs_deferred, xls_gs_immediate | — | erl_parse, hls_actor_source, hls_frame_layout, hls_service_contract, hls_source, lists, maps, xls_callback_lower, xls_dslx, xls_init, xls_names, xls_pattern_lower | — | apps/erl_hls/src/backend/xls/actors/xls_gs_lower.erl | erlang, hls_actor_source, hls_frame_layout, hls_service_contract, lists, xls_callback_lower, xls_dslx, xls_init, xls_names, xls_pattern_lower |
| src/backend/xls/actors/xls_init.erl | xls_init | erl_hls | clause/2, lower/4 emit/3 | xls_actor_codegen, xls_gs_lower, xls_statem_lower | — | erl_anno, erl_parse, hls_source, string, xls_clause_lower, xls_dslx | — | apps/erl_hls/src/backend/xls/actors/xls_init.erl | erl_anno, erlang, hls_source, string, xls_clause_lower, xls_dslx |
| src/backend/xls/actors/xls_statem_callbacks.erl | xls_statem_callbacks | erl_hls | prepare/2 | hls_service_contract, xls_statem_lower, xls_statem_plan | — | erl_parse, hls_source, lists | — | apps/erl_hls/src/backend/xls/actors/xls_statem_callbacks.erl | erlang, lists |
| src/backend/xls/actors/xls_statem_codegen.erl | xls_statem_codegen | erl_hls | artifact/1, emit/1 body/1 | xls_parse, xls_scheduler_codegen, xls_statem_lower | — | admission_out, admission_pending, admission_valid, data, egress, egress_in, egress_out, egress_ready, egress_valid, enter_pending, entered_from, entry_effect_index, ext_recv, failure, frame, lists, machine, maps, next_event, occupied, phase, postponed, received, replies, req_in, slots, xls_actor_codegen, xls_actor_observation, xls_emitted, xls_names, xls_statem_event_codegen, xls_statem_gather_codegen, xls_statem_reply_codegen | — | apps/erl_hls/src/backend/xls/actors/xls_statem_codegen.erl | erlang, lists, xls_actor_codegen, xls_actor_observation, xls_emitted, xls_names, xls_statem_event_codegen, xls_statem_gather_codegen, xls_statem_reduction_service_codegen, xls_statem_reply_codegen |
| src/backend/xls/actors/xls_statem_continuation.erl | xls_statem_continuation | erl_hls | names/1, groups/2, normalize/4 lower/6 | xls_statem_lower, xls_statem_reduction_lower | — | erl_parse, hls_continuation, hls_source, lists, xls_callback_lower, xls_failure_sites, xls_names, xls_pattern_lower | — | apps/erl_hls/src/backend/xls/actors/xls_statem_continuation.erl | erlang, hls_continuation, hls_source, lists, xls_callback_lower, xls_failure_sites, xls_names, xls_pattern_lower |
| src/backend/xls/actors/xls_statem_entry.erl | xls_statem_entry | erl_hls | analyze/3 effects/1, max_effects/1, map_leaves/2 | xls_statem_lower | — | erl_anno, erl_parse, lists, maps, xls_callback_result, xls_entry_storage, xls_statem_gather_lower, xls_statem_reduction_lower | — | apps/erl_hls/src/backend/xls/actors/xls_statem_entry.erl | erl_parse, erlang, lists, maps, xls_callback_result, xls_entry_storage, xls_statem_gather_lower, xls_statem_reduction_lower |
| src/backend/xls/actors/xls_statem_event_codegen.erl | xls_statem_event_codegen | erl_hls | optional/2, functions/1 direct_step/1, completion_bindings/2 | xls_actor_codegen, xls_collection_codegen, xls_gather_codegen, xls_indexed_collection_codegen, xls_local_owner, xls_machine_codegen, xls_reduction_service_codegen, xls_scheduler_codegen, xls_statem_codegen, xls_statem_gather_codegen, xls_statem_reduction_service_codegen | — | data, egress_valid, enter_pending, entered_from, event, failure, frame, machine, maps, next_event, phase, phase_boundary, postponed, replies, reply, reply_valid, xls_dslx, xls_names, xls_statem_gather_codegen, xls_statem_reply_codegen | — | apps/erl_hls/src/backend/xls/actors/xls_statem_event_codegen.erl | erlang, xls_names, xls_statem_gather_codegen, xls_statem_reply_codegen |
| src/backend/xls/actors/xls_statem_gather_codegen.erl | xls_statem_gather_codegen | erl_hls | progress_width/1, payload_width/1, storage_width/1, declarations/1, functions/1 optional/2, field/1, copy/1, entry_fields/3, entry_bindings/1, next_field/1, entry_commit/1, tags/2 dispatch_bindings/1, ordinary_dispatch/2, direct_complete/1, direct_effective/2, direct_failure/2, receive_gate/1 | hls_actor_interface, xls_actor_codegen, xls_gather_codegen, xls_reduction_service_codegen, xls_statem_codegen, xls_statem_event_codegen, xls_statem_reduction_service_codegen | — | data, directive, dispatched, enter_pending, entered_from, failure, frame, gather, key, lists, maps, member, next_event, outcome, phase, phase_boundary, postponed, progress, raw, remaining, repeat_phase, seen, status, valid, value, values, xls_dslx, xls_names, xls_statem_event_codegen, xls_statem_gather_layout, xls_statem_gather_lower, xls_statem_reduction_ir, xls_statem_reduction_service_codegen, xls_struct_codec | — | apps/erl_hls/src/backend/xls/actors/xls_statem_gather_codegen.erl | erlang, lists, xls_dslx, xls_names, xls_statem_event_codegen, xls_statem_gather_layout, xls_statem_gather_lower, xls_statem_reduction_ir, xls_statem_reduction_service_codegen, xls_struct_codec |
| src/backend/xls/actors/xls_statem_gather_layout.erl | xls_statem_gather_layout | erl_hls | progress/1, codec/1 | hls_protocol_inspection, xls_statem_gather_codegen | — | hls_field_layout, hls_nums, lists, maps, xls_named_bits | — | apps/erl_hls/src/backend/xls/actors/xls_statem_gather_layout.erl | erlang, hls_field_layout, hls_nums, lists, maps, xls_named_bits |
| src/backend/xls/actors/xls_statem_gather_lower.erl | xls_statem_gather_lower | erl_hls | parse_open/2, split_internal/1 analyze/3, interface/1, records/1 | xls_statem_entry, xls_statem_gather_codegen, xls_statem_lower | — | hls_records, hls_source, lists, maps, xls_callback_lower, xls_callback_result, xls_failure_sites, xls_names, xls_pattern_lower, xls_statem_reduction_lower | — | apps/erl_hls/src/backend/xls/actors/xls_statem_gather_lower.erl | erlang, hls_records, lists, maps, xls_callback_lower, xls_callback_result, xls_failure_sites, xls_names, xls_pattern_lower, xls_statem_reduction_lower |
| src/backend/xls/actors/xls_statem_lower.erl | xls_statem_lower | erl_hls | interface/2, interface/3 artifact/3, artifact/4, planned_artifact/3, planned_artifact/4 lower/3, lower/4 | hls_pack, xls_parse, xls_phase_specialize, xls_phase_values, xls_statem_plan | — | enter_pending, erl_anno, erl_parse, file, hls_actor_source, hls_frame_layout, hls_records, hls_service_contract, hls_source, hls_type, lists, maps, xls_actor_codegen, xls_actor_observation, xls_callback_lower, xls_callback_result, xls_clause_lower, xls_dslx_imports, xls_entry_storage, xls_failure_sites, xls_hardware_source, xls_helpers, xls_init, xls_names, xls_pattern_lower, xls_record_codegen, xls_statem_callbacks, xls_statem_codegen, xls_statem_continuation, xls_statem_entry, xls_statem_gather_lower, xls_statem_plan, xls_statem_reduction_ir, xls_statem_reduction_lower, xls_statem_reply_codegen | file:filename | apps/erl_hls/src/backend/xls/actors/xls_statem_lower.erl | erlang, hls_actor_source, hls_frame_layout, hls_records, hls_service_contract, hls_source, hls_type, lists, maps, xls_actor_codegen, xls_actor_observation, xls_callback_lower, xls_callback_result, xls_clause_lower, xls_dslx_imports, xls_entry_storage, xls_failure_sites, xls_hardware_source, xls_helpers, xls_init, xls_names, xls_pattern_lower, xls_record_codegen, xls_statem_callbacks, xls_statem_codegen, xls_statem_continuation, xls_statem_entry, xls_statem_gather_lower, xls_statem_plan, xls_statem_reduction_ir, xls_statem_reduction_lower, xls_statem_reply_codegen |
| src/backend/xls/actors/xls_statem_plan.erl | xls_statem_plan | erl_hls | from_file/2, from_file/3 build/5 validate/3, records/1, callbacks/1, select/2, provenance/1, manifest/1, identity/1 | hls_local_actor, hls_protocol_application_binding, hls_protocol_capture, hls_protocol_identity, hls_protocol_inventory, hls_protocol_schema, hls_protocol_transport, xls_actor_program, xls_message_facts, xls_statem_lower | — | binary, crypto, erl_parse, file, filename, hls_frame_layout, hls_source, lists, maps, point, xls_actor_codegen, xls_statem_callbacks, xls_statem_lower | file:filename | apps/erl_hls/src/backend/xls/actors/xls_statem_plan.erl | binary, crypto, erlang, filename, hls_frame_layout, hls_source, lists, maps, xls_statem_callbacks, xls_statem_lower, xls_statem_plan |
| src/backend/xls/actors/xls_statem_reduction_codegen.erl | xls_statem_reduction_codegen | erl_hls | declarations/1, functions/1 private_width/1, tag_member/2, site_contributions/1 | xls_actor_codegen, xls_exclusive_collection_codegen, xls_machine_layout, xls_reduction_codegen | — | accumulator, data, directive, dispatched, expected, failure, frame, key, lists, maps, member, next_event, outcome, phase, raw, reduction, remaining, repeat_phase, seen, site, state, status, valid, value, xls_dslx, xls_names, xls_statem_reduction_ir | — | apps/erl_hls/src/backend/xls/actors/xls_statem_reduction_codegen.erl | erlang, lists, xls_dslx, xls_names, xls_statem_reduction_ir |
| src/backend/xls/actors/xls_statem_reduction_ir.erl | xls_statem_reduction_ir | erl_hls | new/4, interface/1 layout/1, packed_layout/1, storage_width/1, interface_storage_width/1, observation_fields/1 site_count/1, max_population/1, max_member_count/1, type_width/1, site_width/1, remaining_width/1, member_width/1, has_runtime_members/1 | hls_actor_interface, hls_protocol_inspection, xls_actor_codegen, xls_actor_observation, xls_collection_observation, xls_exclusive_collection_codegen, xls_indexed_collection_codegen, xls_reduction_codegen, xls_reduction_service_codegen, xls_scheduler_debug, xls_scheduler_ram_v, xls_statem_gather_codegen, xls_statem_lower, xls_statem_reduction_codegen, xls_statem_reduction_lower, xls_statem_reduction_service_codegen | — | hls_type, lists, maps, xls_dslx | — | apps/erl_hls/src/backend/xls/actors/xls_statem_reduction_ir.erl | erlang, hls_type, lists, maps, xls_dslx |
| src/backend/xls/actors/xls_statem_reduction_lower.erl | xls_statem_reduction_lower | erl_hls | analyze/2, analyze_interface/2 internal_groups/2, split_entry_actions/2, normalize_completion/3 collection_type/2, collection_open/3, collection_contributions/6 | xls_statem_entry, xls_statem_gather_lower, xls_statem_lower | — | erl_anno, erl_parse, hls_records, hls_source, hls_type, lists, maps, xls_callback_lower, xls_callback_result, xls_clause_lower, xls_failure_sites, xls_names, xls_pattern_lower, xls_pattern_totality, xls_statem_continuation, xls_statem_reduction_ir, xls_type_shape | — | apps/erl_hls/src/backend/xls/actors/xls_statem_reduction_lower.erl | erlang, hls_records, hls_type, lists, maps, xls_callback_lower, xls_callback_result, xls_failure_sites, xls_names, xls_pattern_lower, xls_pattern_totality, xls_statem_continuation, xls_statem_reduction_ir, xls_type_shape |
| src/backend/xls/actors/xls_statem_reduction_service_codegen.erl | xls_statem_reduction_service_codegen | erl_hls | machine_state_field/1, machine_state_copy_field/1 event_tail/2, entry_bindings/1 direct_after_failed/2, direct_after_failed/3, direct_dispatch_bindings/2, direct_effective_binding/1, direct_failed_binding/1, direct_reduction_field/1, direct_entry_bindings/1, direct_entry_reduction_field/1, direct_receive_gate/1 | xls_reduction_service_codegen, xls_statem_gather_codegen | — | admission_pending, admission_valid, data, enter_pending, entered_from, execution, lists, machine, next_event, phase, postponed, reduction, slots, xls_statem_event_codegen, xls_statem_gather_codegen, xls_statem_reduction_ir, xls_statem_reply_codegen | — | apps/erl_hls/src/backend/xls/actors/xls_statem_reduction_service_codegen.erl | erlang, lists, xls_statem_event_codegen, xls_statem_gather_codegen, xls_statem_reply_codegen |
| src/backend/xls/actors/xls_statem_reply_codegen.erl | xls_statem_reply_codegen | erl_hls | enabled/1, width/1, count/1, layout/1 optional/2, declarations/1, functions/1, initial/1 admit/3, finish/2, effect/1 | xls_actor_codegen, xls_collection_codegen, xls_direct_collection_codegen, xls_event_codegen, xls_gather_codegen, xls_indexed_collection_codegen, xls_local_owner, xls_machine_codegen, xls_machine_layout, xls_reduction_service_codegen, xls_scheduler_codegen, xls_statem_codegen, xls_statem_event_codegen, xls_statem_lower, xls_statem_reduction_service_codegen | — | admission_error, allowed, dispatched, enter_pending, failure, frame, from, input, layout, lists, maps, next_event, payloads, received, replies, reply, reply_valid, tag, xls_dslx, xls_names | — | apps/erl_hls/src/backend/xls/actors/xls_statem_reply_codegen.erl | erlang, lists, maps, xls_names |
| src/backend/xls/analysis/xls_hardware_source.erl | xls_hardware_source | erl_hls | select/2, statem/2 | hls_pack, xls_gs_deferred, xls_gs_immediate, xls_helpers, xls_phase_values, xls_statem_lower | — | hls_records, hls_source, lists, maps, validation | — | apps/erl_hls/src/backend/xls/analysis/xls_hardware_source.erl | erlang, hls_records, hls_source, lists, maps |
| src/backend/xls/analysis/xls_known_bits.erl | xls_known_bits | erl_hls | unknown/0, literal/1, invert/1, combine/3 for_type/2 | xls_entry_storage | — | hls_type | — | apps/erl_hls/src/backend/xls/analysis/xls_known_bits.erl | erlang, hls_type |
| src/backend/xls/analysis/xls_message_bits.erl | xls_message_bits | erl_hls | frame/2, frame/3 join/1, join_cases/1 | hls_protocol_codec_plan, hls_protocol_schema, xls_message_facts | — | hls_frame_layout, hls_nums, hls_type, lists, maps | — | apps/erl_hls/src/backend/xls/analysis/xls_message_bits.erl | erlang, hls_frame_layout, hls_type, lists, maps |
| src/backend/xls/analysis/xls_message_facts.erl | xls_message_facts | erl_hls | from_file/2, from_file/3, validate/3 on_ports/2, frame_bits/2, frame_cases/2, manifest/1 | — | — | binary, bounds, file, hls_frame_layout, hls_source, hls_type, lists, maps, xls_actor_codegen, xls_message_bits, xls_statem_plan | file:filename | apps/erl_hls/src/backend/xls/analysis/xls_message_facts.erl | binary, erlang, hls_frame_layout, hls_type, lists, maps, xls_message_bits, xls_message_facts, xls_statem_plan |
| src/backend/xls/analysis/xls_pattern_totality.erl | xls_pattern_totality | erl_hls | prove/2, shape_fields/1 assertions/2 | xls_statem_reduction_lower | — | erl_parse, lists, maps, xls_type_shape | — | apps/erl_hls/src/backend/xls/analysis/xls_pattern_totality.erl | erlang, lists |
| src/backend/xls/analysis/xls_phase_eval.erl | xls_phase_eval | erl_hls | context/1, unknown/0, record/2 call/3, clause/3, concrete/2 | xls_phase_values | — | erl_parse, erlang, hls_records, hls_source, lists, maps | apply | apps/erl_hls/src/backend/xls/analysis/xls_phase_eval.erl | erlang, hls_records, lists, maps |
| src/backend/xls/analysis/xls_phase_specialize.erl | xls_phase_specialize | erl_hls | from_file/2, from_file/3 | — | — | erl_anno, file, hls_frame_layout, hls_source, lists, xls_actor_codegen, xls_phase_values, xls_statem_lower | file:filename | apps/erl_hls/src/backend/xls/analysis/xls_phase_specialize.erl | erl_anno, erlang, hls_frame_layout, hls_source, lists, xls_phase_values, xls_statem_lower |
| src/backend/xls/analysis/xls_phase_values.erl | xls_phase_values | erl_hls | from_file/2, from_file/3, analyze/2 validate/3, manifest/1, field/3 | xls_phase_specialize | — | binary, crypto, file, hls_frame_layout, hls_records, hls_source, lists, maps, point, xls_actor_codegen, xls_hardware_source, xls_phase_eval, xls_statem_lower | file:filename | apps/erl_hls/src/backend/xls/analysis/xls_phase_values.erl | binary, crypto, erlang, hls_frame_layout, hls_records, hls_source, lists, maps, xls_hardware_source, xls_phase_eval, xls_phase_values, xls_statem_lower |
| src/backend/xls/analysis/xls_type_shape.erl | xls_type_shape | erl_hls | records/2 | xls_pattern_totality, xls_statem_reduction_lower | — | file, filelib, filename, hls_records, hls_source, lists, maps | file:filename | apps/erl_hls/src/backend/xls/analysis/xls_type_shape.erl | erlang, filename, hls_records, hls_source, lists, maps |
| src/backend/xls/emission/xls_dslx.erl | xls_dslx | erl_hls | ref/1, field/2, index/2, slice/3, call/2, literal/2, tuple/1, construct/2, construct/3 bind/2, block/2, choose/3, match/2, binary/3, unary/2, cast/2 failure_ref/1, indent/2 validate/1, render/1 | xls_actor_codegen, xls_binary_lower, xls_callback_lower, xls_case_lower, xls_clause_lower, xls_collection_codegen, xls_comparison, xls_direct_collection_codegen, xls_emitted, xls_entry_storage, xls_exclusive_collection_codegen, xls_failure_sites, xls_gs_deferred, xls_gs_lower, xls_helpers, xls_indexed_collection_codegen, xls_init, xls_parse_io, xls_pattern_lower, xls_protocol_partition, xls_protocol_transport, xls_provider_bits, xls_provider_bool, xls_provider_fixed, xls_provider_lists, xls_provider_nums, xls_provider_vec, xls_reduction_codegen, xls_statem_event_codegen, xls_statem_gather_codegen, xls_statem_reduction_codegen, xls_statem_reduction_ir, xls_statem_reply_codegen, xls_struct_codec, xls_type | — | lists, xls_clause_lower, xls_failure_sites, xls_parse_io | — | apps/erl_hls/src/backend/xls/emission/xls_dslx.erl | erlang, lists, xls_failure_sites, xls_parse_io |
| src/backend/xls/emission/xls_dslx_imports.erl | xls_dslx_imports | erl_hls | from_forms/1 emit/2 | xls_actor_codegen, xls_gs_deferred, xls_gs_immediate, xls_names, xls_statem_lower | — | code, erlang, hls_source, lists, maps, re, string, xls_names, xls_type | code:ensure_loaded | apps/erl_hls/src/backend/xls/emission/xls_dslx_imports.erl | code, erlang, hls_source, lists, maps, re, string, xls_names, xls_type |
| src/backend/xls/emission/xls_emitted.erl | xls_emitted | erl_hls | new/2, new/3 bytes/1, sites/1, sites/2 with_bytes/2 | hls_compile, hls_local_actor, hls_scheduler_build, phi_decoder_profile_build, phi_partition_ram, snowflake_actor_topology, telemetry, xls_activation_codegen, xls_actor_codegen, xls_actor_debug, xls_gs_deferred, xls_gs_immediate, xls_local_owner, xls_parse, xls_protocol_inbox, xls_scheduler_actor, xls_scheduler_codegen, xls_scheduler_debug, xls_statem_codegen | — | crypto, maps, xls_dslx, xls_failure_sites | — | apps/erl_hls/src/backend/xls/emission/xls_emitted.erl | crypto, erlang, maps, xls_dslx, xls_failure_sites |
| src/backend/xls/emission/xls_failure_sites.erl | xls_failure_sites | erl_hls | prepare/1, at/2, generic/0 allocate/2, number/1, reference/1, declarations/1 validate_locations/1, validate_sites/2, from_catalog/2 | hls_actor_interface, hls_local_actor, xls_actor_codegen, xls_actor_debug, xls_binary_lower, xls_case_lower, xls_clause_lower, xls_dslx, xls_emitted, xls_gs_deferred, xls_gs_immediate, xls_helpers, xls_scheduler_debug, xls_statem_continuation, xls_statem_gather_lower, xls_statem_lower, xls_statem_reduction_lower | — | binary, crypto, erl_anno, erl_parse, file, filename, hls_source, lists, maps, string, unicode, xls_dslx | file:filename | apps/erl_hls/src/backend/xls/emission/xls_failure_sites.erl | binary, crypto, erl_anno, erl_parse, erlang, filename, lists, maps, string, unicode, xls_dslx |
| src/backend/xls/emission/xls_names.erl | xls_names | erl_hls | record_type/1, record_codec/1, enum_member/1, keyword/1, import_alias/1 actor/2, reduction/3, wire_tags/1 | hls_pack, hls_partition_dslx, hls_partition_outbox, xls_actor_codegen, xls_case_lower, xls_clause_lower, xls_dslx_imports, xls_entry_storage, xls_exclusive_collection_codegen, xls_fabric_topology_instance_dslx, xls_fabric_topology_profile, xls_gs_deferred, xls_gs_immediate, xls_gs_lower, xls_helpers, xls_indexed_collection_codegen, xls_machine_names, xls_pattern_lower, xls_provider_record, xls_record_codegen, xls_reduction_codegen, xls_state_projection, xls_statem_codegen, xls_statem_continuation, xls_statem_event_codegen, xls_statem_gather_codegen, xls_statem_gather_lower, xls_statem_lower, xls_statem_reduction_codegen, xls_statem_reduction_lower, xls_statem_reply_codegen, xls_topology_family_dslx, xls_topology_instance_dslx, xls_topology_profile, xls_topology_scheduler_dslx, xls_topology_source_fragment_dslx | — | erl_anno, hls_actor_source, hls_records, hls_source, lists, maps, re, string, xls_dslx_imports | — | apps/erl_hls/src/backend/xls/emission/xls_names.erl | erl_anno, erlang, hls_actor_source, hls_records, hls_source, lists, maps, re, string, xls_dslx_imports |
| src/backend/xls/emission/xls_parse_io.erl | xls_parse_io | erl_hls | indent/2 | xls_dslx | — | lists, string, xls_dslx | — | apps/erl_hls/src/backend/xls/emission/xls_parse_io.erl | erlang, lists, string |
| src/backend/xls/expressions/xls_binary_lower.erl | xls_binary_lower | erl_hls | prepare/1 construct/2, pattern/2 integer_literal/1 | xls_clause_lower, xls_comparison, xls_helpers, xls_pattern_lower | — | erl_anno, erl_bits, erl_parse, hls_source, lists, xls_clause_lower, xls_dslx, xls_failure_sites, xls_static_integer | — | apps/erl_hls/src/backend/xls/expressions/xls_binary_lower.erl | erl_bits, erlang, lists, xls_clause_lower, xls_dslx, xls_failure_sites, xls_static_integer |
| src/backend/xls/expressions/xls_callback_lower.erl | xls_callback_lower | erl_hls | group_by/2 lower/7 | hls_service_contract, xls_gs_deferred, xls_gs_lower, xls_helpers, xls_statem_continuation, xls_statem_gather_lower, xls_statem_lower, xls_statem_reduction_lower | include "xls_clause_lower.hrl" | bool, erl_parse, lists, xls_clause_lower, xls_dslx, xls_guard_lower, xls_pattern_lower, xls_var_scope | — | apps/erl_hls/src/backend/xls/expressions/xls_callback_lower.erl | erlang, lists, xls_clause_lower, xls_dslx, xls_guard_lower, xls_pattern_lower, xls_var_scope |
| src/backend/xls/expressions/xls_case_lower.erl | xls_case_lower | erl_hls | lower/4, lower_if/3 | xls_clause_lower | include "xls_clause_lower.hrl" | bool, erl_anno, erl_parse, lists, maps, xls_clause_lower, xls_dslx, xls_failure_sites, xls_guard_lower, xls_names, xls_pattern_lower | — | apps/erl_hls/src/backend/xls/expressions/xls_case_lower.erl | erlang, lists, maps, xls_clause_lower, xls_dslx, xls_failure_sites, xls_guard_lower, xls_names, xls_pattern_lower |
| src/backend/xls/expressions/xls_clause_lower.erl | xls_clause_lower | erl_hls | branch_from_clause/4, branch_from_clause/6, clause_outcome/4, statement_from_statement/2 outcome_value/1, failure_expression/1, failure_code/1, add_match_failure/3, add_failure/2 find_binding/3, bind/4, record_raw/2, reference/1, reference/2, instr/2, instr/3 print/1 | hls_pauli, phi_field, xls_actor_codegen, xls_binary_lower, xls_callback_lower, xls_case_lower, xls_comparison, xls_dslx, xls_entry_storage, xls_guard_lower, xls_helpers, xls_init, xls_named_bits, xls_pattern_lower, xls_provider_bits, xls_provider_bool, xls_provider_fixed, xls_provider_float, xls_provider_lists, xls_provider_nums, xls_provider_prng, xls_provider_serial, xls_provider_type, xls_provider_vec, xls_statem_lower, xls_statem_reduction_lower, xls_type | include "xls_clause_lower.hrl" | bool, erl_anno, erl_parse, hls_type, lists, maps, xls_binary_lower, xls_case_lower, xls_comparison, xls_dslx, xls_failure_sites, xls_names, xls_nums, xls_pattern_lower, xls_static_integer, xls_type, xls_var_scope | — | apps/erl_hls/src/backend/xls/expressions/xls_clause_lower.erl | erlang, lists, maps, xls_binary_lower, xls_case_lower, xls_comparison, xls_dslx, xls_failure_sites, xls_names, xls_nums, xls_pattern_lower, xls_static_integer, xls_type, xls_var_scope |
| src/backend/xls/expressions/xls_comparison.erl | xls_comparison | erl_hls | prepare/1 lower/2 | xls_clause_lower, xls_helpers | — | erl_parse, hls_records, hls_source, lists, maps, xls_binary_lower, xls_clause_lower, xls_dslx | — | apps/erl_hls/src/backend/xls/expressions/xls_comparison.erl | erlang, hls_records, lists, maps, xls_binary_lower, xls_dslx |
| src/backend/xls/expressions/xls_guard_lower.erl | xls_guard_lower | erl_hls | condition/3, predicate/2 | xls_callback_lower, xls_case_lower | — | bool, erl_anno, erl_parse, lists, xls_clause_lower | — | apps/erl_hls/src/backend/xls/expressions/xls_guard_lower.erl | erlang, lists |
| src/backend/xls/expressions/xls_helpers.erl | xls_helpers | erl_hls | prepare/2 emit/3 | xls_gs_deferred, xls_gs_immediate, xls_statem_lower | — | erl_anno, erl_parse, hls_actor_source, hls_bool, hls_records, hls_source, hls_type, lists, maps, re, xls_binary_lower, xls_callback_lower, xls_clause_lower, xls_comparison, xls_dslx, xls_failure_sites, xls_hardware_source, xls_literal_types, xls_names, xls_pattern_lower, xls_type | — | apps/erl_hls/src/backend/xls/expressions/xls_helpers.erl | erl_anno, erlang, hls_actor_source, hls_bool, hls_records, hls_source, hls_type, lists, maps, re, xls_binary_lower, xls_callback_lower, xls_clause_lower, xls_comparison, xls_dslx, xls_failure_sites, xls_hardware_source, xls_literal_types, xls_names, xls_pattern_lower, xls_type |
| src/backend/xls/expressions/xls_literal_types.erl | xls_literal_types | erl_hls | clauses/3 format/1 | xls_helpers | — | erl_anno, erl_parse, hls_records, hls_source, hls_type, lists, maps, xls_static_integer, xls_type | — | apps/erl_hls/src/backend/xls/expressions/xls_literal_types.erl | erlang, hls_records, hls_type, lists, maps, xls_static_integer, xls_type |
| src/backend/xls/expressions/xls_pattern_lower.erl | xls_pattern_lower | erl_hls | record_argument/3, value_argument/1, record_pattern_name/1 lower/3, match/3 | hls_service_contract, xls_callback_lower, xls_case_lower, xls_clause_lower, xls_gs_deferred, xls_gs_lower, xls_helpers, xls_statem_continuation, xls_statem_gather_lower, xls_statem_lower, xls_statem_reduction_lower | include "xls_clause_lower.hrl" | bool, erl_anno, erl_parse, lists, maps, xls_binary_lower, xls_clause_lower, xls_dslx, xls_names | — | apps/erl_hls/src/backend/xls/expressions/xls_pattern_lower.erl | erlang, lists, maps, xls_binary_lower, xls_clause_lower, xls_dslx, xls_names |
| src/backend/xls/expressions/xls_static_integer.erl | xls_static_integer | erl_hls | eval/1, operation/2 clauses/1 | xls_binary_lower, xls_clause_lower, xls_literal_types | — | erl_parse, error, lists, maps | apply | apps/erl_hls/src/backend/xls/expressions/xls_static_integer.erl | erlang, lists, maps |
| src/backend/xls/expressions/xls_var_scope.erl | xls_var_scope | erl_hls | annotate/1 | xls_callback_lower, xls_clause_lower | — | erl_parse, lists, maps | — | apps/erl_hls/src/backend/xls/expressions/xls_var_scope.erl | erlang, lists, maps |
| src/backend/xls/topology/xls_topology_dslx.erl | xls_topology_dslx | erl_hls | artifact_requirements/2 emit/2, from_module/2 | phi_noise_topology_dslx, phi_phenom_topology_dslx, phi_repetition_topology, phi_torus_topology_dslx, telemetry, xls_topology_family_dslx | — | hls_topology, xls_topology_profile | — | apps/erl_hls/src/backend/xls/topology/xls_topology_dslx.erl | erlang, hls_topology |
| src/backend/xls/topology/xls_topology_family_dslx.erl | xls_topology_family_dslx | erl_hls | artifact_requirements/2, emit/2 lower/2, lower/3 render/1 | xls_fabric_topology_dslx, xls_fabric_topology_family_dslx | — | actor_debug_out, admission_in, egress_in, frame_out, hls_actor_interface, hls_codec, hls_frame_layout, hls_topology, io_lib, lists, maps, spatial_in, x, xls_actor_observation, xls_frame_layout, xls_names, xls_nums, xls_topology_dslx, xls_topology_ingress, xls_topology_profile, y | — | apps/erl_hls/src/backend/xls/topology/xls_topology_family_dslx.erl | erlang, hls_actor_interface, hls_codec, hls_frame_layout, io_lib, lists, maps, xls_actor_observation, xls_frame_layout, xls_names, xls_nums, xls_topology_ingress, xls_topology_profile |
| src/backend/xls/topology/xls_topology_graph.erl | xls_topology_graph | erl_hls | lower/2, lower/3 lanes/1, check_lanes/3 | hls_protocol_topology, xls_fabric_topology_instance_dslx, xls_topology_instance_dslx | — | hls_actor_interface, hls_codec, hls_frame_layout, lists, maps, xls_nums, xls_topology_profile | — | apps/erl_hls/src/backend/xls/topology/xls_topology_graph.erl | erlang, hls_actor_interface, hls_codec, hls_frame_layout, lists, maps, xls_nums, xls_topology_profile |
| src/backend/xls/topology/xls_topology_ingress.erl | xls_topology_ingress | erl_hls | lower/2 condition/3, target_enum/1 | hls_partition_dslx, hls_partition_ingress_plan, xls_fabric_topology_instance_dslx, xls_topology_family_dslx, xls_topology_instance_dslx, xls_topology_scheduler_dslx | — | hls_actor_interface, hls_type, lists, maps, string, xls_topology_profile | — | apps/erl_hls/src/backend/xls/topology/xls_topology_ingress.erl | erlang, hls_actor_interface, hls_type, lists, maps, string, xls_topology_profile |
| src/backend/xls/topology/xls_topology_instance_dslx.erl | xls_topology_instance_dslx | erl_hls | artifact_requirements/2 emit/2 | — | — | admission_in, egress_in, frame_in, frame_out, hls_topology, io_lib, lists, maps, spatial_in, xls_actor_observation, xls_frame_layout, xls_names, xls_topology_graph, xls_topology_ingress, xls_topology_profile | — | apps/erl_hls/src/backend/xls/topology/xls_topology_instance_dslx.erl | erlang, hls_topology, io_lib, lists, maps, xls_actor_observation, xls_frame_layout, xls_names, xls_topology_graph, xls_topology_ingress, xls_topology_profile |
| src/backend/xls/topology/xls_topology_profile.erl | xls_topology_profile | erl_hls | normalize/1 identifier/2, egress_depth/2 | xls_topology_dslx, xls_topology_family_dslx, xls_topology_graph, xls_topology_ingress, xls_topology_instance_dslx | — | hls_actor_interface, hls_frame_layout, lists, maps, re, xls_actor_observation, xls_names | — | apps/erl_hls/src/backend/xls/topology/xls_topology_profile.erl | erlang, hls_actor_interface, hls_frame_layout, lists, maps, re, xls_actor_observation, xls_names |
| src/backend/xls/types/xls_frame_layout.erl | xls_frame_layout | erl_hls | config/1, assert/1 | hls_compile, hls_frame_layout, hls_local_actor, hls_partition_dslx, hls_protocol_transport, xls_actor_codegen, xls_frame_layout, xls_gs_deferred, xls_gs_immediate, xls_topology_family_dslx, xls_topology_instance_dslx | — | hls_field_layout, hls_frame_layout, xls_frame_layout, xls_struct_codec | — | apps/erl_hls/src/backend/xls/types/xls_frame_layout.erl | erlang, hls_field_layout, hls_frame_layout, xls_struct_codec |
| src/backend/xls/types/xls_named_bits.erl | xls_named_bits | erl_hls | local/2, qualified/3 width/2, zero/2, pack/3, unpack/3 print_type/2, transpile/3 | xls_statem_gather_layout | behavior hls_type, behaviour xls_type | calls, hls_nums, hls_type, xls_clause_lower | — | apps/erl_hls/src/backend/xls/types/xls_named_bits.erl | erlang, hls_nums, hls_type |
| src/backend/xls/types/xls_nums.erl | xls_nums | erl_hls | index_type/1, signed_type/1, unsigned_type/1 unsigned_literal/2, packed_unsigned_literal/1 | hls_partition_dslx, hls_partition_shared_dslx, xls_clause_lower, xls_provider_fixed, xls_provider_lists, xls_provider_serial, xls_topology_family_dslx, xls_topology_graph, xls_topology_scheduler_dslx, xls_topology_source_fragment_dslx | — | hls_codec, lists | — | apps/erl_hls/src/backend/xls/types/xls_nums.erl | erlang, hls_codec, lists |
| src/backend/xls/types/xls_provider_bits.erl | xls_provider_bits | erl_hls | print_type/2, dslx_imports/0, dslx_codec/2, transpile/3 | — | behaviour xls_type | hls_bits, hls_type, xls_clause_lower, xls_dslx, xls_type | — | apps/erl_hls/src/backend/xls/types/xls_provider_bits.erl | erlang, hls_bits, hls_type, xls_clause_lower, xls_type |
| src/backend/xls/types/xls_provider_bool.erl | xls_provider_bool | erl_hls | print_type/2, transpile/3 | — | behaviour xls_type | hls_bool, hls_type, xls_clause_lower, xls_dslx | — | apps/erl_hls/src/backend/xls/types/xls_provider_bool.erl | erlang, hls_bool, xls_clause_lower |
| src/backend/xls/types/xls_provider_fixed.erl | xls_provider_fixed | erl_hls | print_type/2, dslx_imports/0, transpile/3 | — | behaviour xls_type | hls_fixed, hls_type, xls_clause_lower, xls_dslx, xls_nums, xls_type | — | apps/erl_hls/src/backend/xls/types/xls_provider_fixed.erl | erlang, hls_fixed, hls_type, xls_clause_lower, xls_nums, xls_type |
| src/backend/xls/types/xls_provider_float.erl | xls_provider_float | erl_hls | dslx_imports/0, transpile/3 | — | behaviour xls_type | hls_float, hls_type, xls_clause_lower, xls_type | — | apps/erl_hls/src/backend/xls/types/xls_provider_float.erl | erlang, hls_float, hls_type |
| src/backend/xls/types/xls_provider_gs.erl | xls_provider_gs | erl_hls | print_type/2 | — | behaviour xls_type | — | — | apps/erl_hls/src/backend/xls/types/xls_provider_gs.erl | erlang |
| src/backend/xls/types/xls_provider_lists.erl | xls_provider_lists | erl_hls | transpile/3, dslx_imports/1, print_type/2, dslx_codec/2 | xls_provider_vec | behaviour xls_type | binary, hls_lists, hls_type, lists, xls_clause_lower, xls_dslx, xls_nums, xls_type | — | apps/erl_hls/src/backend/xls/types/xls_provider_lists.erl | binary, erlang, hls_lists, hls_type, lists, xls_clause_lower, xls_nums, xls_type |
| src/backend/xls/types/xls_provider_nums.erl | xls_provider_nums | erl_hls | transpile/3, print_type/2, dslx_imports/1, dslx_codec/2 | — | behaviour xls_type | hls_float, hls_nums, hls_type, lists, xls_clause_lower, xls_dslx, xls_type | — | apps/erl_hls/src/backend/xls/types/xls_provider_nums.erl | erlang, hls_float, hls_nums, lists, xls_clause_lower, xls_type |
| src/backend/xls/types/xls_provider_prng.erl | xls_provider_prng | erl_hls | transpile/3 | — | behaviour xls_type | xls_clause_lower | — | apps/erl_hls/src/backend/xls/types/xls_provider_prng.erl | erlang, xls_clause_lower |
| src/backend/xls/types/xls_provider_record.erl | xls_provider_record | erl_hls | print_type/2, dslx_codec/2 | — | behaviour xls_type | hls_record, xls_names, xls_type | — | apps/erl_hls/src/backend/xls/types/xls_provider_record.erl | erlang, xls_names |
| src/backend/xls/types/xls_provider_serial.erl | xls_provider_serial | erl_hls | print_type/2, dslx_imports/0, transpile/3 | — | behaviour xls_type | hls_serial, hls_type, xls_clause_lower, xls_nums, xls_type | — | apps/erl_hls/src/backend/xls/types/xls_provider_serial.erl | erlang, hls_serial, xls_clause_lower, xls_nums, xls_type |
| src/backend/xls/types/xls_provider_type.erl | xls_provider_type | erl_hls | transpile/3 | — | behaviour xls_type | xls_clause_lower, xls_type | — | apps/erl_hls/src/backend/xls/types/xls_provider_type.erl | erlang, xls_type |
| src/backend/xls/types/xls_provider_vec.erl | xls_provider_vec | erl_hls | print_type/2, dslx_imports/1, dslx_codec/2, transpile/3 | — | behaviour xls_type | hls_type, hls_vec, lists, xls_clause_lower, xls_dslx, xls_provider_lists, xls_type | — | apps/erl_hls/src/backend/xls/types/xls_provider_vec.erl | erlang, hls_type, hls_vec, lists, xls_clause_lower, xls_provider_lists |
| src/backend/xls/types/xls_record_codegen.erl | xls_record_codegen | erl_hls | declaration/1, decoder/1, encoder/1 | xls_gs_deferred, xls_gs_immediate, xls_statem_lower | — | hls_field_layout, hls_records, hls_source, xls_names, xls_struct_codec | — | apps/erl_hls/src/backend/xls/types/xls_record_codegen.erl | erlang, hls_field_layout, hls_records, xls_names, xls_struct_codec |
| src/backend/xls/types/xls_struct_codec.erl | xls_struct_codec | erl_hls | declaration/2, decoder/3, encoder/3 | xls_frame_layout, xls_machine_codegen, xls_protocol_envelope, xls_record_codegen, xls_statem_gather_codegen | — | hls_field_layout, lists, raw, xls_dslx, xls_type | — | apps/erl_hls/src/backend/xls/types/xls_struct_codec.erl | erlang, lists, xls_type |
| src/backend/xls/types/xls_type.erl | xls_type | erl_hls | provider/1, transpile/4 print_type/1, dslx_codec/1, dslx_from_bits/2, dslx_to_bits/2 | hls_protocol_projection, hls_protocol_schema, xls_clause_lower, xls_dslx_imports, xls_entry_storage, xls_helpers, xls_literal_types, xls_machine_codegen, xls_provider_bits, xls_provider_fixed, xls_provider_float, xls_provider_lists, xls_provider_nums, xls_provider_record, xls_provider_serial, xls_provider_type, xls_provider_vec, xls_state_projection, xls_struct_codec | — | code, erlang, hls_type, xls_clause_lower, xls_dslx | code:ensure_loaded | apps/erl_hls/src/backend/xls/types/xls_type.erl | code, erlang, hls_type |
| src/backend/xls/xls_parse.erl | xls_parse | erl_hls | to_artifact/1, to_artifact/2, to_xls/1, to_xls/2 actor_artifact/2, actor_artifact/3 actor_interface/1, actor_interface/2, actor_interface/3 | hls_actor_interface, hls_compile, hls_topology_constants, telemetry, xls_scheduler_actor | — | file, hls_frame_layout, hls_service_contract, hls_source, maps, xls_actor_codegen, xls_actor_observation, xls_emitted, xls_gs_deferred, xls_gs_immediate, xls_statem_codegen, xls_statem_lower | file:filename | apps/erl_hls/src/backend/xls/xls_parse.erl | erlang, hls_frame_layout, hls_service_contract, hls_source, maps, xls_actor_observation, xls_emitted, xls_gs_deferred, xls_gs_immediate, xls_statem_codegen, xls_statem_lower |
| src/examples/packed_samples/packed_samples.erl | packed_samples | erl_hls | init/1, handle_call/2, handle_cast/2 | — | behaviour hls_gs, compile {parse_transform, hls_pack} | hls_bits, hls_nums, hls_type | — | apps/erl_hls/src/examples/packed_samples/packed_samples.erl | erlang, hls_bits, hls_gs, hls_nums, hls_type |
| src/examples/regsvc/regsvc.erl | regsvc | erl_hls | ping/2, get/2, set/4, bulk_get/3 start_link/0, stop/1 init/1, handle_call/2, handle_cast/2 | — | behavior hls_gs, compile {parse_transform, hls_pack} | gen_server, hls_gs, hls_lists, hls_nums, hls_type, lists | — | apps/erl_hls/src/examples/regsvc/regsvc.erl | erlang, gen_server, hls_gs, hls_lists, hls_nums, hls_type, lists |
| src/examples/telemetry/telemetry.erl | telemetry | erl_hls | run/1, example_commands/0 write_bundle/1 | — | include "telemetry.hrl" | binary, code, crypto, file, filename, hls_artifact_bundle, hls_compile, hls_frame_layout, hls_statem, hls_topology, json, lists, maps, telemetry_calibrator, xls_emitted, xls_parse, xls_topology_dslx | file:filename, file:write_file | apps/erl_hls/src/examples/telemetry/telemetry.erl | binary, code, crypto, erlang, file, filename, hls_artifact_bundle, hls_compile, hls_frame_layout, hls_statem, hls_topology, json, lists, maps, telemetry_calibrator, xls_emitted, xls_parse, xls_topology_dslx |
| src/examples/telemetry/telemetry_calibrator.erl | telemetry_calibrator | erl_hls | init/1, configuring/3, ready/3, publishing/3 | telemetry | behaviour hls_statem, compile {parse_transform, hls_pack}, include "telemetry.hrl" | hls_bool, hls_nums, hls_statem, hls_type | — | apps/erl_hls/src/examples/telemetry/telemetry_calibrator.erl | erlang, hls_bool, hls_gs, hls_nums, hls_type |
| src/examples/telemetry/telemetry_topology.erl | telemetry_topology | erl_hls | topology/0 | — | — | hls_topology | — | apps/erl_hls/src/examples/telemetry/telemetry_topology.erl | erlang |
| src/examples/telemetry/telemetry_window.erl | telemetry_window | erl_hls | init/1, collecting/3, reporting/3 | — | behaviour hls_statem, compile {parse_transform, hls_pack}, include "telemetry.hrl" | hls_nums, hls_statem, hls_type | — | apps/erl_hls/src/examples/telemetry/telemetry_window.erl | erlang, hls_bool, hls_gs, hls_nums, hls_type |
| src/frontend/hls_actor_constants.erl | hls_actor_constants | erl_hls | analyze/4, from_source/3 constant/1, value/1, unknown_record/2 | hls_topology_constants | — | hls_records, hls_source, hls_type, lists, maps | apply | apps/erl_hls/src/frontend/hls_actor_constants.erl | erlang, hls_records, hls_type, lists, maps |
| src/frontend/hls_actor_interface.erl | hls_actor_interface | erl_hls | from_module/1, from_module/2, from_modules/1, from_modules/2 dispatched_schemas/1, dispatched_schemas/2, initial_effects/1, max_entry_effects/1, output_schemas/2, reduction_storage_width/1, gather_storage_width/1, schema/2, state/1 | hls_host_codec_plan, hls_node_topology, hls_partition, hls_protocol_application_binding, hls_reduction_plan, hls_scheduler_plan, hls_topology, hls_topology_constants, hls_topology_endpoint, hls_topology_family, xls_actor_debug, xls_actor_observation, xls_collection_observation, xls_fabric_topology_dslx, xls_fabric_topology_family_dslx, xls_fabric_topology_instance_dslx, xls_fabric_topology_profile, xls_scheduler_debug, xls_scheduler_ram_v, xls_topology_family_dslx, xls_topology_graph, xls_topology_ingress, xls_topology_profile | — | code, filelib, hls_frame_layout, hls_type, lists, lowerer, maps, proplists, xls_failure_sites, xls_parse, xls_statem_gather_codegen, xls_statem_reduction_ir | code:ensure_loaded | apps/erl_hls/src/frontend/hls_actor_interface.erl | code, erlang, filelib, hls_frame_layout, hls_type, lists, maps, proplists, xls_failure_sites, xls_parse, xls_statem_gather_codegen, xls_statem_reduction_ir |
| src/frontend/hls_actor_source.erl | hls_actor_source | erl_hls | state/1, tags/1, message_words/2, message_words/3 | hls_pack, hls_records, hls_service_contract, xls_gs_deferred, xls_gs_immediate, xls_gs_lower, xls_helpers, xls_names, xls_statem_lower | — | erl_anno, hls_diagnostic, hls_frame_layout, hls_nums, hls_records, hls_source, lists, maps, unicode | — | apps/erl_hls/src/frontend/hls_actor_source.erl | erl_anno, erlang, hls_diagnostic, hls_frame_layout, hls_records, hls_source, lists, unicode |
| src/frontend/hls_pack.erl | hls_pack | erl_hls | parse_transform/2 | — | — | erl_anno, erl_parse, hls_actor_source, hls_records, hls_service_contract, hls_source, hls_type, lists, maps, xls_hardware_source, xls_names, xls_statem_lower | — | apps/erl_hls/src/frontend/hls_pack.erl | erl_anno, erl_parse, erlang, hls_actor_source, hls_records, hls_service_contract, hls_source, hls_type, lists, maps, xls_hardware_source, xls_names, xls_statem_lower |
| src/frontend/hls_records.erl | hls_records | erl_hls | resolve/1, resolve/2, references/1, declarations/2, used/1, wire_names/1, find/2 values/2, fields/1, width/1, field_name/1, validate_defaults/1, is_zero_default/1 | hls_actor_constants, hls_actor_source, hls_pack, hls_protocol_application_binding, hls_topology_constants, xls_comparison, xls_entry_storage, xls_gs_deferred, xls_gs_immediate, xls_hardware_source, xls_helpers, xls_literal_types, xls_names, xls_phase_eval, xls_phase_values, xls_record_codegen, xls_state_projection, xls_statem_gather_lower, xls_statem_lower, xls_statem_reduction_lower, xls_type_shape | — | erl_parse, hls_actor_source, hls_record, hls_source, hls_type, lists | — | apps/erl_hls/src/frontend/hls_records.erl | erlang, hls_actor_source, hls_record, hls_source, hls_type, lists |
| src/frontend/hls_service_contract.erl | hls_service_contract | erl_hls | from_forms/1, groups/2, call_arity/1 | hls_pack, xls_gs_deferred, xls_gs_immediate, xls_gs_lower, xls_parse, xls_statem_lower | — | erl_parse, hls_actor_source, hls_continuation, hls_service_schema, hls_source, lists, maps, xls_callback_lower, xls_pattern_lower, xls_statem_callbacks | — | apps/erl_hls/src/frontend/hls_service_contract.erl | erlang, hls_actor_source, hls_continuation, hls_source, lists, maps, xls_callback_lower, xls_pattern_lower, xls_statem_callbacks |
| src/frontend/hls_source.erl | hls_source | erl_hls | capture/2, from_forms/2, options/2 read/2, parse_file/1, parse_file/2 find_attribute/2, find_optional_attribute/2, find_function/3, find_spec/3 | hls_actor_constants, hls_actor_source, hls_build_sources, hls_compile, hls_compile_cli, hls_local_actor, hls_pack, hls_protocol_transport, hls_records, hls_scheduler_build, hls_service_contract, hls_source, hls_source_config, hls_topology_constants, xls_actor_program, xls_binary_lower, xls_comparison, xls_dslx_imports, xls_entry_storage, xls_failure_sites, xls_gs_deferred, xls_gs_immediate, xls_gs_lower, xls_hardware_source, xls_helpers, xls_init, xls_literal_types, xls_message_facts, xls_names, xls_parse, xls_phase_eval, xls_phase_specialize, xls_phase_values, xls_record_codegen, xls_scheduler_actor, xls_state_projection, xls_statem_callbacks, xls_statem_continuation, xls_statem_gather_lower, xls_statem_lower, xls_statem_plan, xls_statem_reduction_lower, xls_type_shape | — | code, epp, erl_anno, erl_features, erl_parse, erl_scan, file, filename, hls_diagnostic, hls_source, lists, maps, peer, unicode | file:filename, file:format_error, file:get_cwd | apps/erl_hls/src/frontend/hls_source.erl | code, epp, erl_anno, erl_features, erlang, file, filename, hls_diagnostic, lists, maps, peer, unicode |
| src/toolchain/hls_artifact_bundle.erl | hls_artifact_bundle | erl_hls | open/1, snapshot/2, finish/3 | hls_build_support, hls_compile, hls_scheduler_build, hls_source_build, telemetry | — | binary, crypto, file, filelib, filename, json, lists, maps, unicode | file:filename, file:filename_all, file:list_dir, file:make_dir, file:read_file, file:write_file | apps/erl_hls/src/toolchain/hls_artifact_bundle.erl | binary, crypto, erlang, file, filelib, filename, json, lists, maps, unicode |
| src/toolchain/hls_cli.erl | hls_cli | erl_hls | main/2 options/2, required/2, integer/2 | hls_compile_cli, hls_fabric_cli, phi_protocol_cli | — | error, hls_diagnostic, init, io, json, lists, maps, os, unicode | — | apps/erl_hls/src/toolchain/hls_cli.erl | erlang, hls_diagnostic, init, io, json, lists, maps, os, unicode |
| src/toolchain/hls_compile.erl | hls_compile | erl_hls | actor/3 support/2, support/3, configure_support/2, support_layout/1 | hls_build_support, hls_compile_cli, hls_scheduler_build, hls_source_build, telemetry | — | binary, code, crypto, file, filelib, filename, hls_artifact_bundle, hls_diagnostic, hls_frame_layout, hls_source, io_lib, json, lists, maps, string, unicode, xls_emitted, xls_frame_layout, xls_parse | code:priv_dir, file:filename, file:list_dir, file:read_file_info, file:write_file | apps/erl_hls/src/toolchain/hls_compile.erl | binary, code, crypto, erlang, file, filelib, filename, hls_artifact_bundle, hls_diagnostic, hls_frame_layout, io_lib, json, lists, maps, string, unicode, xls_emitted, xls_frame_layout, xls_parse |
| src/toolchain/hls_compile_cli.erl | hls_compile_cli | erl_hls | main/0, run/1 | — | — | erl_parse, erl_scan, file, hls_cli, hls_compile, hls_diagnostic, hls_source, io, lists, maps, string, unicode | file:consult | apps/erl_hls/src/toolchain/hls_compile_cli.erl | erl_parse, erl_scan, erlang, file, hls_cli, hls_compile, hls_diagnostic, io, lists, maps, string, unicode |
| src/topology/hls_topology.erl | hls_topology | erl_hls | from_module/1, normalize/1 routes_for_instance/3 | hls_counter_example, hls_node_topology, hls_partition, hls_partition_ingress_plan, hls_partition_reduction, hls_protocol_inventory, hls_protocol_topology, hls_protocol_transport, hls_reduction_plan, hls_scheduler_build, hls_scheduler_plan, hls_shared_debug_catalog, hls_topology_constants, phi_decoder_profile_build, phi_decoder_profile_topology, phi_decoder_profile_topology_dslx, phi_memory_boundary, phi_memory_cpu_fabric, phi_noise_topology, phi_noise_topology_dslx, phi_phenom_topology, phi_repetition_topology, phi_shared_noise_topology_dslx, phi_torus_topology, snowflake_actor_run, snowflake_actor_topology, snowflake_source, telemetry, telemetry_topology, xls_actor_debug, xls_actor_observation, xls_fabric_topology_dslx, xls_fabric_topology_family_dslx, xls_fabric_topology_instance_dslx, xls_scheduler_debug, xls_topology_dslx, xls_topology_family_dslx, xls_topology_instance_dslx | — | code, erlang, hls_actor_interface, hls_topology_endpoint, hls_topology_family, lists, maps, outputs, restart | code:ensure_loaded | apps/erl_hls/src/topology/hls_topology.erl | code, erlang, hls_actor_interface, hls_topology_endpoint, hls_topology_family, lists, maps |
| src/topology/hls_topology_endpoint.erl | hls_topology_endpoint | erl_hls | actor/3, validate_route/5, require_schemas/4 | hls_topology, hls_topology_family | — | hls_actor_interface, lists, maps | — | apps/erl_hls/src/topology/hls_topology_endpoint.erl | erlang, hls_actor_interface, lists, maps |
| src/topology/hls_topology_family.erl | hls_topology_family | erl_hls | normalize/3, routes_for_instance/3 | hls_topology | — | erlang, hls_actor_interface, hls_topology_endpoint, lists, maps, small | — | apps/erl_hls/src/topology/hls_topology_family.erl | erlang, hls_actor_interface, hls_topology_endpoint, lists, maps |

## hls_fabric modules

| Source / responsibility | Module | Current and Stage 1 app | Explicit exports | Candidate consumers | Compile declarations | Remote references | Resource or dispatch calls | Stage 1 path | BEAM imports |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| apps/hls_lowering/src/backend/sv/sv_protocol_application.erl | sv_protocol_application | hls_lowering | emit/2 write/3 | hls_protocol_application | — | file, filename, hls_frame_layout, lists, sv_protocol_inspection | file:filename, file:write_file | apps/hls_lowering/src/backend/sv/sv_protocol_application.erl | erlang, file, filename, hls_frame_layout, lists, sv_protocol_inspection |
| apps/hls_lowering/src/backend/sv/sv_protocol_inspection.erl | sv_protocol_inspection | hls_lowering | ports/1, body/1 | sv_protocol_application | — | binary | — | apps/hls_lowering/src/backend/sv/sv_protocol_inspection.erl | binary, erlang |
| apps/hls_lowering/src/backend/sv/sv_protocol_ports.erl | sv_protocol_ports | hls_lowering | emit/2, emit/4 write/3, write/5 | xls_protocol_boundary, xls_protocol_bridge, xls_protocol_network, xls_protocol_transport | — | file, lists, re | file:filename, file:write_file | apps/hls_lowering/src/backend/sv/sv_protocol_ports.erl | erlang, file, lists, re |
| apps/hls_lowering/src/backend/sv/xls_scheduler_ram_v.erl | xls_scheduler_ram_v | hls_lowering | bindings/1, bindings/2, bindings/3, configurations/1, mailbox_stride/2 wires/1, application_ports/1, instances/2 assets/1 | hls_scheduler_build, phi_decoder_profile_build, phi_decoder_profile_top_v, phi_memory_debug_top_v, phi_partition_ram, snowflake_actor_topology | — | code, file, filename, hls_actor_interface, hls_frame_layout, hls_scheduler_plan, lists, maps, xls_collection_observation, xls_machine_layout, xls_scheduler_ram_dslx, xls_statem_reduction_ir | code:priv_dir, file:filename | apps/hls_lowering/src/backend/sv/xls_scheduler_ram_v.erl | code, erlang, filename, hls_actor_interface, hls_frame_layout, lists, maps, xls_collection_observation, xls_machine_layout, xls_scheduler_ram_dslx, xls_statem_reduction_ir |
| apps/hls_lowering/src/backend/xls/execution/xls_event_codegen.erl | xls_event_codegen | hls_lowering | shared_dispatch/1 | xls_machine_codegen | — | maps, xls_gather_codegen, xls_indexed_memory_codegen, xls_reduction_service_codegen, xls_statem_reply_codegen | — | apps/hls_lowering/src/backend/xls/execution/xls_event_codegen.erl | erlang, xls_gather_codegen, xls_indexed_memory_codegen, xls_reduction_service_codegen, xls_statem_reply_codegen |
| apps/hls_lowering/src/backend/xls/execution/xls_gather_codegen.erl | xls_gather_codegen | hls_lowering | enabled/1, progress_width/1, storage_width/1 decode/2, encode/2, helpers/1, shared_dispatch/2 state_fields/1, selection_helpers/1, issue_bindings/1, retire/1 | hls_scheduler_plan, xls_activation_codegen, xls_event_codegen, xls_machine_codegen, xls_machine_layout, xls_scheduler_codegen | — | aggregate, cursor, dispatched, egress, entry, failure, frame, gather, gather_candidates, in_flight, indexed_candidates, mail, maps, progress, storage, values, widths, xls_actor_codegen, xls_collection_observation, xls_reduction_service_codegen, xls_statem_event_codegen, xls_statem_gather_codegen, xls_statem_reply_codegen | — | apps/hls_lowering/src/backend/xls/execution/xls_gather_codegen.erl | erlang, xls_actor_codegen, xls_collection_observation, xls_reduction_service_codegen, xls_statem_event_codegen, xls_statem_gather_codegen, xls_statem_reply_codegen |
| apps/hls_lowering/src/backend/xls/execution/xls_indexed_memory_codegen.erl | xls_indexed_memory_codegen | hls_lowering | optional/2 request_fields/1, loader_bindings/1, dispatch/2 | xls_event_codegen, xls_machine_codegen, xls_scheduler_codegen | — | dispatched, failure, gather_failure, gather_progress, gather_read_req_out, gather_read_resp_in, gather_valid, gather_values, maps | — | apps/hls_lowering/src/backend/xls/execution/xls_indexed_memory_codegen.erl | erlang |
| apps/hls_lowering/src/backend/xls/execution/xls_machine_codegen.erl | xls_machine_codegen | hls_lowering | state_type/1, step_type/0, executor_types/1, codec/1, decode/3 step/1, execute/1 | xls_activation_codegen, xls_scheduler_codegen | — | data, directive, dispatched, effects, effects_valid, egress_blocked, egress_ready, enter_pending, entered_from, frame, machine, mailbox_index, maps, next_event, order_index, phase, phase_boundary, received, replies, reply, reply_valid, slot, xls_actor_codegen, xls_event_codegen, xls_gather_codegen, xls_indexed_memory_codegen, xls_machine_layout, xls_state_projection, xls_statem_event_codegen, xls_statem_reply_codegen, xls_struct_codec, xls_type | — | apps/hls_lowering/src/backend/xls/execution/xls_machine_codegen.erl | erlang, xls_actor_codegen, xls_event_codegen, xls_gather_codegen, xls_indexed_memory_codegen, xls_machine_layout, xls_reduction_service_codegen, xls_state_projection, xls_statem_event_codegen, xls_statem_reply_codegen, xls_struct_codec, xls_type |
| apps/hls_lowering/src/backend/xls/execution/xls_machine_names.erl | xls_machine_names | hls_lowering | validate/1 | xls_activation_codegen, xls_scheduler_codegen | — | lists, maps, xls_names | — | apps/hls_lowering/src/backend/xls/execution/xls_machine_names.erl | erlang, lists, xls_names |
| apps/hls_lowering/src/backend/xls/execution/xls_reduction_service_codegen.erl | xls_reduction_service_codegen | hls_lowering | shared_machine_support/2, shared_machine_support/3, shared_executor_dispatch/2, shared_dispatch_bindings/3, shared_dispatch_effective_binding/2, shared_dispatch_effective_binding/3, shared_dispatch_failed_binding/2, shared_dispatch_failed_binding/3, shared_dispatch_reduction_field/2, shared_dispatch_dispatched_field/2, shared_dispatch_dispatched_field/3, shared_entry_step/1, shared_entry_step/2 shared_state_fields/2, shared_executor_request_field/2, shared_executor_request_value/2, shared_proc_field/2, shared_config_parameter/2, shared_config_endpoint/2 shared_service_helpers/2, shared_retire_binding/2, shared_issue_bindings/2, shared_capture/2, shared_capture_token/2, shared_state_source/2, shared_post_issue_state/2, shared_post_issue_state_name/2 | xls_event_codegen, xls_gather_codegen, xls_local_owner | — | aggregate, aggregate_in, aggregate_pending_valid, aggregate_valid, application, cursor, data, directive, dispatched, effects_valid, egress, egress_blocked, enter_pending, entered_from, entry, failure, gather, in_flight, internal, internal_candidates, machine, mail, maps, next_event, phase, reduction, slot, valid, xls_statem_event_codegen, xls_statem_gather_codegen, xls_statem_reduction_ir, xls_statem_reduction_service_codegen, xls_statem_reply_codegen | — | apps/hls_lowering/src/backend/xls/execution/xls_reduction_service_codegen.erl | erlang, xls_statem_event_codegen, xls_statem_gather_codegen, xls_statem_reduction_service_codegen, xls_statem_reply_codegen |
| apps/hls_lowering/src/backend/xls/execution/xls_state_projection.erl | xls_state_projection | hls_lowering | validate/3, width/1 functions/1, decode/4, encode/2, parameter/1, argument/1 manifest/1 | xls_activation_codegen, xls_machine_codegen, xls_machine_layout, xls_scheduler_actor, xls_scheduler_codegen, xls_scheduler_debug | — | binary, crypto, hls_records, hls_source, hls_type, lists, maps, raw, slot, xls_names, xls_type | — | apps/hls_lowering/src/backend/xls/execution/xls_state_projection.erl | binary, crypto, erlang, hls_records, hls_type, lists, maps, xls_names, xls_type |
| apps/hls_lowering/src/backend/xls/partition/hls_partition_dslx.erl | hls_partition_dslx | hls_lowering | emit/3 | — | — | egress_in, frame_out, header, hls_partition, hls_partition_links, hls_partition_outbox, hls_partition_reduction, hls_partition_reduction_dslx, hls_partition_shared_dslx, hls_partition_tile, index, lists, maps, op, payload_words, points, routed_in, spatial_in, xls_fabric_topology_profile, xls_frame_layout, xls_names, xls_nums, xls_topology_ingress | — | apps/hls_lowering/src/backend/xls/partition/hls_partition_dslx.erl | erlang, hls_partition, hls_partition_links, hls_partition_outbox, hls_partition_reduction, hls_partition_reduction_dslx, hls_partition_shared_dslx, hls_partition_tile, lists, xls_fabric_topology_profile, xls_frame_layout, xls_names, xls_nums, xls_topology_ingress |
| apps/hls_lowering/src/backend/xls/partition/hls_partition_links.erl | hls_partition_links | hls_lowering | configure/2, width/1, ports/1 imports/1, parameters/1, frame_parameters/1, frame_names/1, frame_arguments/1, channel/3 frame_channels/1, spawn/1 | hls_partition_dslx, hls_partition_outbox, hls_partition_reduction_dslx, phi_partition_ram, xls_partition_application | — | hls_partition_reduction, lists, maps | — | apps/hls_lowering/src/backend/xls/partition/hls_partition_links.erl | erlang, hls_partition_reduction, lists, maps |
| apps/hls_lowering/src/backend/xls/partition/hls_partition_outbox.erl | hls_partition_outbox | hls_lowering | lanes/2, ordinary/2 support/1, spawn/3 | hls_partition_dslx, hls_partition_shared_dslx | — | binary, code, file, filename, hls_partition_links, hls_partition_reduction, hls_partition_reduction_dslx, hls_partition_tile, lists, xls_actor_outbox_dslx, xls_names | code:priv_dir, file:read_file | apps/hls_lowering/src/backend/xls/partition/hls_partition_outbox.erl | binary, code, erlang, file, filename, hls_partition_links, hls_partition_reduction, hls_partition_reduction_dslx, hls_partition_tile, lists, xls_actor_outbox_dslx, xls_names |
| apps/hls_lowering/src/backend/xls/partition/hls_partition_reduction_dslx.erl | hls_partition_reduction_dslx | hls_lowering | support/2, channels/2, aggregate_parameter/2 spawn/2, collector/3, outbox_input/2 | hls_partition_dslx, hls_partition_outbox, hls_partition_shared_dslx | — | aggregate, binary, code, file, filename, hls_partition_links, hls_partition_reduction, hls_partition_tile, lists, opened | code:priv_dir, file:read_file | apps/hls_lowering/src/backend/xls/partition/hls_partition_reduction_dslx.erl | binary, code, erlang, file, filename, hls_partition_links, hls_partition_reduction, hls_partition_tile, lists |
| apps/hls_lowering/src/backend/xls/partition/hls_partition_shared_dslx.erl | hls_partition_shared_dslx | hls_lowering | support/1, parameters/1, names/1 channels/2, spawn/2 input/3, ingress_support/3, egress/2 | hls_partition_dslx, xls_partition_application | — | binary, code, credit, file, filename, frame, header, hls_frame_layout, hls_partition_outbox, hls_partition_reduction_dslx, index, lists, maps, op, payload_words, request_out, slot, values, xls_actor_outbox_dslx, xls_nums, xls_scheduler_ram_dslx | code:priv_dir, file:read_file | apps/hls_lowering/src/backend/xls/partition/hls_partition_shared_dslx.erl | binary, code, erlang, file, filename, hls_frame_layout, hls_partition_outbox, hls_partition_reduction_dslx, lists, xls_actor_outbox_dslx, xls_nums, xls_scheduler_ram_dslx |
| apps/hls_lowering/src/backend/xls/partition/hls_partition_tile.erl | hls_partition_tile | hls_lowering | prepare/3, schedule/3, local/2, incoming/2, planning/1, projection/2 parameters/1, names/1, constants/2, lane_id/1 | hls_partition, hls_partition_dslx, hls_partition_outbox, hls_partition_reduction_dslx, hls_partition_tile_debug, phi_partition_ram, xls_partition_application | — | binary, hls_actor_identity, hls_frame_layout, hls_partition_schedule, io_lib, lists, maps | — | apps/hls_lowering/src/backend/xls/partition/hls_partition_tile.erl | binary, erlang, hls_actor_identity, hls_frame_layout, hls_partition_schedule, io_lib, lists, maps |
| apps/hls_lowering/src/backend/xls/partition/xls_actor_outbox_dslx.erl | xls_actor_outbox_dslx | hls_lowering | name/1, emit/1 | hls_partition_outbox, hls_partition_shared_dslx | — | binary, code, file, filename | code:priv_dir, file:read_file | apps/hls_lowering/src/backend/xls/partition/xls_actor_outbox_dslx.erl | binary, code, erlang, file, filename |
| apps/hls_lowering/src/backend/xls/partition/xls_partition_application.erl | xls_partition_application | hls_lowering | emit/3 | — | — | app_in, app_out, hls_diagnostic, hls_frame_layout, hls_partition_links, hls_partition_shared_dslx, hls_partition_tile, lists, maps, tile_gateway, tile_host | — | apps/hls_lowering/src/backend/xls/partition/xls_partition_application.erl | erlang, hls_diagnostic, hls_frame_layout, hls_partition_links, hls_partition_shared_dslx, hls_partition_tile, lists |
| apps/hls_lowering/src/backend/xls/protocol/hls_local_actor.erl | hls_local_actor | hls_lowering | prepare/2, prepare/3, descriptor/1 render/1, compile/2, manifest/1 emit/2, write/2, write/3 | hls_protocol_application_binding, hls_protocol_arithmetic, hls_protocol_control, hls_protocol_identity, hls_protocol_inbox, hls_protocol_inspection, hls_protocol_mixed, hls_protocol_schema, hls_protocol_source, hls_protocol_transport, hls_source_build, xls_local_owner, xls_protocol_inbox | — | file, filename, hls_build_profile, hls_diagnostic, hls_frame_layout, hls_generated_files, hls_protocol_inbox, hls_source, io_lib, json, lists, maps, unicode, xls_activation_codegen, xls_actor_program, xls_emitted, xls_entry_storage, xls_failure_sites, xls_frame_layout, xls_local_owner, xls_machine_layout, xls_protocol_inbox, xls_statem_plan | file:filename, file:read_file, file:read_link_info, file:write_file | apps/hls_lowering/src/backend/xls/protocol/hls_local_actor.erl | erlang, file, filename, hls_build_profile, hls_diagnostic, hls_frame_layout, hls_generated_files, io_lib, json, lists, maps, unicode, xls_activation_codegen, xls_actor_program, xls_emitted, xls_entry_storage, xls_frame_layout, xls_local_owner, xls_machine_layout, xls_statem_plan |
| apps/hls_lowering/src/backend/xls/protocol/hls_protocol_application.erl | hls_protocol_application | hls_lowering | plan/1, descriptor/1, transport/1 emit/1, write/2 | hls_source_build | — | binary, crypto, file, hls_diagnostic, hls_generated_files, hls_protocol_application_binding, hls_protocol_application_schema, hls_protocol_boundary, hls_protocol_control, hls_protocol_identity, hls_protocol_transport, hls_source_config, io_lib, json, maps, sv_protocol_application, xls_protocol_application | file:filename | apps/hls_lowering/src/backend/xls/protocol/hls_protocol_application.erl | binary, crypto, erlang, hls_diagnostic, hls_generated_files, hls_protocol_application_binding, hls_protocol_boundary, hls_protocol_control, hls_protocol_identity, hls_protocol_transport, hls_source_config, io_lib, json, maps, sv_protocol_application, xls_protocol_application |
| apps/hls_lowering/src/backend/xls/protocol/hls_protocol_boundary.erl | hls_protocol_boundary | hls_lowering | plan/2, descriptor/1, transport/1 emit/1, emit/2, write/2, write/3 | hls_protocol_application, hls_protocol_bridge, hls_source_build, xls_protocol_bridge | — | file, hls_generated_files, hls_protocol_network, hls_protocol_transport, hls_source_config, maps, math, xls_protocol_boundary, xls_protocol_network | file:filename | apps/hls_lowering/src/backend/xls/protocol/hls_protocol_boundary.erl | erlang, hls_generated_files, hls_protocol_network, hls_protocol_transport, hls_source_config, maps, math, xls_protocol_boundary |
| apps/hls_lowering/src/backend/xls/protocol/hls_protocol_bridge.erl | hls_protocol_bridge | hls_lowering | plan/2, descriptor/1, transport/1 emit/1, emit/2, write/2, write/3 | hls_protocol_deployment, hls_protocol_mixed, hls_source_build, xls_protocol_bridge | — | code, crypto, file, filename, hls_diagnostic, hls_frame_layout, hls_generated_files, hls_protocol_boundary, hls_protocol_control, hls_protocol_identity, hls_protocol_partition, hls_protocol_transport, hls_source_config, lists, maps, xls_protocol_boundary, xls_protocol_bridge, xls_protocol_network | code:priv_dir, file:filename, file:read_file | apps/hls_lowering/src/backend/xls/protocol/hls_protocol_bridge.erl | code, crypto, erlang, file, filename, hls_diagnostic, hls_generated_files, hls_protocol_boundary, hls_protocol_control, hls_protocol_identity, hls_protocol_transport, hls_source_config, lists, maps, xls_protocol_bridge |
| apps/hls_lowering/src/backend/xls/protocol/hls_protocol_deployment.erl | hls_protocol_deployment | hls_lowering | plan/1, descriptor/1, routing/1, transports/1 emit/1, write/2 | hls_source_build | — | deployment, file, hls_diagnostic, hls_generated_files, hls_protocol_application_binding, hls_protocol_application_schema, hls_protocol_bridge, hls_protocol_routing, hls_protocol_topology, hls_protocol_transport, hls_source_config, lists, maps | file:filename | apps/hls_lowering/src/backend/xls/protocol/hls_protocol_deployment.erl | erlang, hls_diagnostic, hls_generated_files, hls_protocol_application_binding, hls_protocol_bridge, hls_protocol_routing, hls_protocol_transport, hls_source_config, lists, maps |
| apps/hls_lowering/src/backend/xls/protocol/hls_protocol_inspection.erl | hls_protocol_inspection | hls_lowering | mode/1 emit/1, write/2 | xls_protocol_boundary, xls_protocol_network | — | binary, crypto, file, hls_actor_identity, hls_generated_files, hls_local_actor, hls_protocol_identity, hls_protocol_transport, hls_topology_debug, initialized, io_lib, json, lists, maps, raw, reset, xls_actor_debug, xls_actor_observation, xls_actor_program, xls_protocol_network, xls_statem_gather_layout, xls_statem_reduction_ir | file:filename | apps/hls_lowering/src/backend/xls/protocol/hls_protocol_inspection.erl | binary, crypto, erlang, hls_actor_identity, hls_generated_files, hls_protocol_identity, hls_topology_debug, io_lib, json, lists, maps, xls_actor_debug, xls_actor_observation, xls_actor_program, xls_statem_gather_layout, xls_statem_reduction_ir |
| apps/hls_lowering/src/backend/xls/protocol/hls_protocol_mixed.erl | hls_protocol_mixed | hls_lowering | plan/1, descriptor/1, transport/1 emit/1, write/2 | hls_source_build | — | file, hls_diagnostic, hls_generated_files, hls_host_codec, hls_local_actor, hls_protocol_application_binding, hls_protocol_application_schema, hls_protocol_bridge, hls_protocol_mixed_schema, hls_protocol_partition, hls_protocol_topology, hls_protocol_transport, hls_source_config, lists, maps, xls_actor_program | file:filename | apps/hls_lowering/src/backend/xls/protocol/hls_protocol_mixed.erl | erlang, hls_diagnostic, hls_generated_files, hls_protocol_application_binding, hls_protocol_bridge, hls_protocol_transport, hls_source_config, lists, maps, xls_actor_program |
| apps/hls_lowering/src/backend/xls/protocol/hls_protocol_network.erl | hls_protocol_network | hls_lowering | plan/2, descriptor/1, phases/1, transport/1 emit/1, emit/2, write/2, write/3 | hls_protocol_boundary, hls_source_build, xls_protocol_boundary, xls_protocol_network | — | file, hls_diagnostic, hls_generated_files, hls_protocol_transport, hls_source_config, lists, maps, xls_protocol_network | file:filename | apps/hls_lowering/src/backend/xls/protocol/hls_protocol_network.erl | erlang, hls_diagnostic, hls_generated_files, hls_protocol_transport, hls_source_config, lists, maps, xls_protocol_network |
| apps/hls_lowering/src/backend/xls/protocol/hls_protocol_transport.erl | hls_protocol_transport | hls_lowering | prepare/1, plan/1, plan/2 bundle/1, control/1, descriptor/1 emit/1, write/2 | hls_protocol_application, hls_protocol_application_binding, hls_protocol_boundary, hls_protocol_bridge, hls_protocol_deployment, hls_protocol_inspection, hls_protocol_mixed, hls_protocol_network, hls_protocol_partition, hls_source_build, xls_protocol_network | — | erlang, file, filename, hls_build_sources, hls_diagnostic, hls_frame_layout, hls_generated_files, hls_local_actor, hls_protocol_arithmetic, hls_protocol_capture, hls_protocol_control, hls_protocol_fabric, hls_protocol_inbox, hls_protocol_inventory, hls_protocol_model, hls_protocol_partition, hls_protocol_source, hls_protocol_topology, hls_protocol_transactions, hls_source, hls_source_config, hls_topology, json, lists, maps, proplists, unicode, xls_actor_program, xls_frame_layout, xls_local_owner, xls_protocol_inbox, xls_protocol_transport, xls_statem_plan | apply, file:filename | apps/hls_lowering/src/backend/xls/protocol/hls_protocol_transport.erl | erlang, filename, hls_build_sources, hls_diagnostic, hls_frame_layout, hls_generated_files, hls_local_actor, hls_protocol_arithmetic, hls_protocol_capture, hls_protocol_control, hls_protocol_fabric, hls_protocol_inbox, hls_protocol_inventory, hls_protocol_model, hls_protocol_partition, hls_protocol_source, hls_protocol_topology, hls_protocol_transactions, hls_source_config, hls_topology, json, lists, maps, proplists, unicode, xls_actor_program, xls_frame_layout, xls_local_owner, xls_protocol_inbox, xls_protocol_transport, xls_statem_plan |
| apps/hls_lowering/src/backend/xls/protocol/xls_activation_codegen.erl | xls_activation_codegen | hls_lowering | artifact/1, emit/1 | hls_local_actor | — | code, file, filename, lists, maps, xls_actor_codegen, xls_emitted, xls_gather_codegen, xls_machine_codegen, xls_machine_names, xls_state_projection, xls_template | code:priv_dir, file:read_file | apps/hls_lowering/src/backend/xls/protocol/xls_activation_codegen.erl | code, erlang, file, filename, lists, maps, xls_actor_codegen, xls_emitted, xls_gather_codegen, xls_machine_codegen, xls_machine_names, xls_state_projection, xls_template |
| apps/hls_lowering/src/backend/xls/protocol/xls_local_owner.erl | xls_local_owner | hls_lowering | ports/1, ports/2 import_owner/2 | hls_local_actor, hls_protocol_transport | — | binary, builder, code, completion_granted, crypto, file, filename, frame, hls_local_actor, next_event, xls_actor_codegen, xls_emitted, xls_reduction_service_codegen, xls_statem_event_codegen, xls_statem_reply_codegen, xls_template | code:priv_dir, file:read_file | apps/hls_lowering/src/backend/xls/protocol/xls_local_owner.erl | binary, code, crypto, erlang, file, filename, xls_actor_codegen, xls_emitted, xls_reduction_service_codegen, xls_statem_event_codegen, xls_statem_reply_codegen, xls_template |
| apps/hls_lowering/src/backend/xls/protocol/xls_protocol_application.erl | xls_protocol_application | hls_lowering | emit/1 write/2 | hls_protocol_application | — | code, file, filename, hls_generated_files, lists | code:priv_dir, file:filename, file:read_file | apps/hls_lowering/src/backend/xls/protocol/xls_protocol_application.erl | code, erlang, file, filename, hls_generated_files, lists |
| apps/hls_lowering/src/backend/xls/protocol/xls_protocol_arithmetic.erl | xls_protocol_arithmetic | hls_lowering | state/1, steps/1, updates/1 inputs/2 | xls_protocol_network | — | completion_action, lists | — | apps/hls_lowering/src/backend/xls/protocol/xls_protocol_arithmetic.erl | erlang, lists |
| apps/hls_lowering/src/backend/xls/protocol/xls_protocol_bits.erl | xls_protocol_bits | hls_lowering | expression/2 | xls_protocol_inbox, xls_protocol_transport | — | hls_protocol_projection, lists | — | apps/hls_lowering/src/backend/xls/protocol/xls_protocol_bits.erl | erlang, lists |
| apps/hls_lowering/src/backend/xls/protocol/xls_protocol_boundary.erl | xls_protocol_boundary | hls_lowering | plan/1, descriptor/1 emit/2 | hls_protocol_boundary, hls_protocol_bridge, xls_protocol_bridge | — | code, file, filename, hls_frame_layout, hls_generated_files, hls_protocol_inspection, hls_protocol_network, json, lists, maps, sv_protocol_ports, xls_protocol_network, xls_template | code:priv_dir, file:read_file | apps/hls_lowering/src/backend/xls/protocol/xls_protocol_boundary.erl | code, erlang, file, filename, hls_frame_layout, hls_generated_files, json, lists, sv_protocol_ports, xls_template |
| apps/hls_lowering/src/backend/xls/protocol/xls_protocol_bridge.erl | xls_protocol_bridge | hls_lowering | emit/3 | hls_protocol_bridge | — | binary, code, file, filename, frame, free, hls_frame_layout, hls_generated_files, hls_protocol_boundary, hls_protocol_bridge, hls_protocol_control, hls_protocol_partition, json, link, lists, maps, slot, sv_protocol_ports, valid, xls_protocol_boundary, xls_protocol_network, xls_protocol_partition, xls_template | code:priv_dir, file:read_file | apps/hls_lowering/src/backend/xls/protocol/xls_protocol_bridge.erl | binary, code, erlang, file, filename, hls_generated_files, json, lists, maps, sv_protocol_ports, xls_protocol_partition, xls_template |
| apps/hls_lowering/src/backend/xls/protocol/xls_protocol_codec.erl | xls_protocol_codec | hls_lowering | emit/2 write/3 | xls_protocol_partition | — | decoded_ready, encoded_ready, file, frame, frame_valid, hls_frame_layout, hls_protocol_codec, lists, maps, payload, payload_valid, re | file:filename, file:posix, file:write_file | apps/hls_lowering/src/backend/xls/protocol/xls_protocol_codec.erl | erlang, file, hls_frame_layout, lists, maps, re |
| apps/hls_lowering/src/backend/xls/protocol/xls_protocol_envelope.erl | xls_protocol_envelope | hls_lowering | emit/0 | xls_protocol_envelope | — | hls_field_layout, hls_protocol_envelope, xls_protocol_envelope, xls_struct_codec | — | apps/hls_lowering/src/backend/xls/protocol/xls_protocol_envelope.erl | erlang, hls_field_layout, hls_protocol_envelope, xls_struct_codec |
| apps/hls_lowering/src/backend/xls/protocol/xls_protocol_inbox.erl | xls_protocol_inbox | hls_lowering | attach/2 | hls_local_actor, hls_protocol_inbox, hls_protocol_transport | — | code, completion_action, completion_granted, file, filename, hls_frame_layout, hls_local_actor, hls_protocol_inbox, index, lists, maps, xls_emitted, xls_protocol_bits, xls_template | code:priv_dir, file:read_file | apps/hls_lowering/src/backend/xls/protocol/xls_protocol_inbox.erl | code, erlang, file, filename, hls_frame_layout, hls_protocol_inbox, lists, maps, xls_emitted, xls_protocol_bits, xls_template |
| apps/hls_lowering/src/backend/xls/protocol/xls_protocol_ingress.erl | xls_protocol_ingress | hls_lowering | emit/1 write/2 | xls_protocol_network | — | code, file, filename, lists, mask, present, valid, value, x, y | code:priv_dir, file:filename, file:read_file, file:write_file | apps/hls_lowering/src/backend/xls/protocol/xls_protocol_ingress.erl | code, erlang, file, filename, lists |
| apps/hls_lowering/src/backend/xls/protocol/xls_protocol_network.erl | xls_protocol_network | hls_lowering | plan/1, descriptor/1, phases/1 emit/3 | hls_protocol_boundary, hls_protocol_bridge, hls_protocol_inspection, hls_protocol_network, xls_protocol_boundary, xls_protocol_bridge | — | activation, code, file, filename, hls_frame_layout, hls_generated_files, hls_protocol_arithmetic, hls_protocol_capture, hls_protocol_codec, hls_protocol_control, hls_protocol_fabric, hls_protocol_inbox, hls_protocol_inspection, hls_protocol_model, hls_protocol_network, hls_protocol_partition, hls_protocol_source, hls_protocol_topology, hls_protocol_transactions, hls_protocol_transport, host_frame, host_valid, ingress, ingress_fault, ingress_ready, inspect_value, io_lib, json, lists, maps, output_ready, reset, running, start_ready, sv_protocol_ports, xls_protocol_arithmetic, xls_protocol_ingress, xls_protocol_partition, xls_protocol_transport, xls_template | code:priv_dir, file:read_file | apps/hls_lowering/src/backend/xls/protocol/xls_protocol_network.erl | code, erlang, file, filename, hls_generated_files, hls_protocol_control, hls_protocol_inbox, hls_protocol_inspection, io_lib, json, lists, maps, sv_protocol_ports, xls_protocol_arithmetic, xls_protocol_ingress, xls_protocol_partition, xls_template |
| apps/hls_lowering/src/backend/xls/protocol/xls_protocol_partition.erl | xls_protocol_partition | hls_lowering | ports/1, wiring/1, name/1, files/1 emit/1, write/2 | xls_protocol_bridge, xls_protocol_network, xls_protocol_transport | — | composition, file, hls_frame_layout, hls_generated_files, hls_protocol_fabric, hls_protocol_partition, lists, maps, xls_dslx, xls_protocol_codec | file:filename | apps/hls_lowering/src/backend/xls/protocol/xls_protocol_partition.erl | erlang, hls_frame_layout, hls_generated_files, lists, xls_dslx, xls_protocol_codec |
| apps/hls_lowering/src/backend/xls/protocol/xls_protocol_transport.erl | xls_protocol_transport | hls_lowering | plan/1, descriptor/1 emit/1 | hls_protocol_transport, xls_protocol_network | — | code, file, filename, hls_generated_files, hls_protocol_fabric, hls_protocol_projection, hls_protocol_source, json, lists, maps, program, sv_protocol_ports, xls_dslx, xls_protocol_bits, xls_protocol_partition, xls_template | code:priv_dir, file:read_file | apps/hls_lowering/src/backend/xls/protocol/xls_protocol_transport.erl | code, erlang, file, filename, hls_generated_files, json, lists, maps, sv_protocol_ports, xls_dslx, xls_protocol_bits, xls_protocol_partition, xls_template |
| apps/hls_lowering/src/backend/xls/scheduler/xls_collection_codegen.erl | xls_collection_codegen | hls_lowering | validate/2, requirements/3 helpers/1, state_fields/1, ticket_field/1, ticket_value/1, loader_value/1, captured_field/1 retire/1, retire_binding/1, admit/1, admission_guard/1, commit/1, resolve/1, selection/2, issue/1, capture/1 | xls_fabric_topology_instance_dslx, xls_scheduler_actor, xls_scheduler_codegen | — | code, collection, collection_failure, collection_initialized, collection_inputs, file, filename, frame, lists, maps, xls_actor_codegen, xls_dslx, xls_exclusive_collection_codegen, xls_machine_layout, xls_statem_event_codegen, xls_statem_reply_codegen | code:priv_dir, file:filename, file:read_file | apps/hls_lowering/src/backend/xls/scheduler/xls_collection_codegen.erl | code, erlang, file, filename, lists, xls_actor_codegen, xls_exclusive_collection_codegen, xls_machine_layout, xls_statem_event_codegen, xls_statem_reply_codegen |
| apps/hls_lowering/src/backend/xls/scheduler/xls_collection_observation.erl | xls_collection_observation | hls_lowering | enabled/1, width/1, layout/1, binding/1, binding/2 declarations/1, proc_field/1, config_parameter/1, config_value/1, sample/1, state_fields/1, retire/1 top_ports/1, spawn_argument/1, wires/1, ports/1 | xls_fabric_topology_instance_dslx, xls_gather_codegen, xls_scheduler_codegen, xls_scheduler_debug, xls_scheduler_ram_v | — | collection_debug_out, enter_pending, expected, failure, gather_observations, hls_actor_interface, initialized, key, lists, maps, phase, reduction, seen, status, xls_actor_observation, xls_statem_reduction_ir | — | apps/hls_lowering/src/backend/xls/scheduler/xls_collection_observation.erl | erlang, hls_actor_interface, lists, maps, xls_actor_observation, xls_statem_reduction_ir |
| apps/hls_lowering/src/backend/xls/scheduler/xls_direct_collection_codegen.erl | xls_direct_collection_codegen | hls_lowering | validate/2 body/1 | xls_scheduler_actor, xls_scheduler_codegen | — | code, file, filename, maps, xls_actor_observation, xls_dslx, xls_exclusive_collection_codegen, xls_statem_reply_codegen, xls_template | code:priv_dir, file:read_file | apps/hls_lowering/src/backend/xls/scheduler/xls_direct_collection_codegen.erl | code, erlang, file, filename, xls_actor_observation, xls_exclusive_collection_codegen, xls_statem_reply_codegen, xls_template |
| apps/hls_lowering/src/backend/xls/scheduler/xls_effect_window_dslx.erl | xls_effect_window_dslx | hls_lowering | channels/1, spawn/1, arguments/2 | xls_fabric_topology_instance_dslx, xls_topology_scheduler_dslx | — | lists | — | apps/hls_lowering/src/backend/xls/scheduler/xls_effect_window_dslx.erl | erlang, lists |
| apps/hls_lowering/src/backend/xls/scheduler/xls_exclusive_collection_codegen.erl | xls_exclusive_collection_codegen | hls_lowering | validate/1, actor_spec/1 declarations/1, helpers/1, core/1 | xls_collection_codegen, xls_direct_collection_codegen, xls_scheduler_codegen | — | binary, code, contract, failure, file, filename, frame, lists, logger, maps, xls_actor_codegen, xls_dslx, xls_machine_layout, xls_names, xls_reduction_codegen, xls_statem_reduction_codegen, xls_statem_reduction_ir | code:priv_dir, file:read_file | apps/hls_lowering/src/backend/xls/scheduler/xls_exclusive_collection_codegen.erl | binary, code, erlang, file, filename, lists, logger, xls_actor_codegen, xls_machine_layout, xls_names, xls_reduction_codegen, xls_statem_reduction_codegen, xls_statem_reduction_ir |
| apps/hls_lowering/src/backend/xls/scheduler/xls_fabric_topology_dslx.erl | xls_fabric_topology_dslx | hls_lowering | plan/2, analysis/1, descriptor/1, artifact_requirements/1 emit/1 artifact_requirements/2, emit/2, from_module/2 | hls_scheduler_build, phi_decoder_profile_build, phi_decoder_profile_topology_dslx, phi_shared_noise_topology_dslx, xls_scheduler_debug | — | hls_actor_interface, hls_frame_layout, hls_scheduler_plan, hls_topology, maps, xls_fabric_topology_family_dslx, xls_fabric_topology_instance_dslx, xls_fabric_topology_profile, xls_topology_family_dslx, xls_topology_scheduler_dslx, xls_topology_scheduler_plan | — | apps/hls_lowering/src/backend/xls/scheduler/xls_fabric_topology_dslx.erl | erlang, hls_frame_layout, hls_scheduler_plan, hls_topology, maps, xls_fabric_topology_family_dslx, xls_fabric_topology_instance_dslx, xls_fabric_topology_profile, xls_topology_family_dslx, xls_topology_scheduler_dslx, xls_topology_scheduler_plan |
| apps/hls_lowering/src/backend/xls/scheduler/xls_fabric_topology_instance_dslx.erl | xls_fabric_topology_instance_dslx | hls_lowering | required/2, lower/4, lower/2 message_inputs/2, render/1 | xls_fabric_topology_dslx | — | admission_in, egress_in, frame_in, frame_out, hls_actor_interface, hls_frame_layout, hls_scheduler_plan, hls_topology, hls_topology_constants, index, io_lib, lists, maps, request_out, slot, spatial_in, xls_actor_observation, xls_collection_codegen, xls_collection_observation, xls_effect_window_dslx, xls_fabric_topology_profile, xls_names, xls_parallel_effect_router_dslx, xls_scheduler_codegen, xls_scheduler_observation, xls_scheduler_ram_dslx, xls_topology_effect_windows, xls_topology_graph, xls_topology_ingress, xls_topology_scheduler_dslx | — | apps/hls_lowering/src/backend/xls/scheduler/xls_fabric_topology_instance_dslx.erl | erlang, hls_frame_layout, hls_scheduler_plan, hls_topology, hls_topology_constants, io_lib, lists, maps, xls_actor_observation, xls_collection_codegen, xls_collection_observation, xls_effect_window_dslx, xls_fabric_topology_profile, xls_names, xls_parallel_effect_router_dslx, xls_scheduler_codegen, xls_scheduler_observation, xls_scheduler_ram_dslx, xls_topology_effect_windows, xls_topology_graph, xls_topology_ingress, xls_topology_scheduler_dslx |
| apps/hls_lowering/src/backend/xls/scheduler/xls_indexed_collection_codegen.erl | xls_indexed_collection_codegen | hls_lowering | validate/2 imports/1, declarations/1, helpers/1, state_fields/1, ticket_field/1, ticket_value/1 resolve/1, retire/1, admit/1, commit/1, issue/1 | xls_scheduler_actor, xls_scheduler_codegen | — | actor_opened, code, consumed, consuming, current, deferred_failure, deferred_frame, deferred_frame_valid, deferred_write, failure, file, filename, frame, frame_valid, gather_failure, gather_lease, gather_progress, gather_valid, header, indexed_candidates, indexed_cursor, indexed_dirty, indexed_input, indexed_prepared_slot, indexed_prepared_valid, indexed_retirement, indexed_retirement_valid, initialized, intent, key, lists, logger, maps, member, provisional, representative_bank, representative_valid, representative_write, representatives, reserved, valid, value, waiting, write_valid, xls_actor_codegen, xls_dslx, xls_names, xls_statem_event_codegen, xls_statem_reduction_ir, xls_statem_reply_codegen | code:priv_dir, file:read_file | apps/hls_lowering/src/backend/xls/scheduler/xls_indexed_collection_codegen.erl | code, erlang, file, filename, lists, logger, xls_actor_codegen, xls_dslx, xls_names, xls_statem_event_codegen, xls_statem_reduction_ir, xls_statem_reply_codegen |
| apps/hls_lowering/src/backend/xls/scheduler/xls_parallel_effect_router_dslx.erl | xls_parallel_effect_router_dslx | hls_lowering | emit/6 | xls_fabric_topology_instance_dslx | — | binary, code, credit_out, file, filename, lists, scheduled_in, string, window_grant_in, window_release_out, window_request_out, xls_template | code:priv_dir, file:read_file | apps/hls_lowering/src/backend/xls/scheduler/xls_parallel_effect_router_dslx.erl | binary, code, erlang, file, filename, lists, string, xls_template |
| apps/hls_lowering/src/backend/xls/scheduler/xls_publication_codegen.erl | xls_publication_codegen | hls_lowering | plan/1 helpers/1 | xls_scheduler_codegen | — | base, hls_frame_layout, hls_type, index, lists, maps | — | apps/hls_lowering/src/backend/xls/scheduler/xls_publication_codegen.erl | erlang, hls_frame_layout, hls_type, lists |
| apps/hls_lowering/src/backend/xls/scheduler/xls_reduction_codegen.erl | xls_reduction_codegen | hls_lowering | declarations/2, functions/2 transport_function/1, transport_function/2 | xls_exclusive_collection_codegen, xls_scheduler_codegen | — | accumulator, count, failure, frame, frames, key, lists, maps, member, seen, site, slot, state, valid, value, xls_dslx, xls_names, xls_statem_reduction_codegen, xls_statem_reduction_ir | — | apps/hls_lowering/src/backend/xls/scheduler/xls_reduction_codegen.erl | erlang, lists, maps, xls_dslx, xls_names, xls_statem_reduction_codegen, xls_statem_reduction_ir |
| apps/hls_lowering/src/backend/xls/scheduler/xls_scheduler_actor.erl | xls_scheduler_actor | hls_lowering | to_artifact/1, to_artifact/2 to_xls/1, to_xls/2 | hls_scheduler_build, phi_decoder_profile_build | — | code, file, filelib, filename, hls_frame_layout, hls_source, lists, maps, xls_actor_observation, xls_collection_codegen, xls_direct_collection_codegen, xls_emitted, xls_indexed_collection_codegen, xls_parse, xls_scheduler_codegen, xls_scheduler_observation, xls_state_projection | file:filename | apps/hls_lowering/src/backend/xls/scheduler/xls_scheduler_actor.erl | code, erlang, filelib, filename, hls_frame_layout, hls_source, lists, maps, xls_actor_observation, xls_collection_codegen, xls_direct_collection_codegen, xls_emitted, xls_indexed_collection_codegen, xls_parse, xls_scheduler_codegen, xls_scheduler_observation, xls_state_projection |
| apps/hls_lowering/src/backend/xls/scheduler/xls_scheduler_codegen.erl | xls_scheduler_codegen | hls_lowering | artifact/1, emit/1 publication_depth/0 | xls_fabric_topology_instance_dslx, xls_scheduler_actor, xls_topology_scheduler_dslx | — | addr, admission_cursor, code, completed_valid, cursor, data, egress_busy, egress_ready, egress_waiters, entry_probes, file, filename, gather_write_pending, in_flight, index, instance_id, lists, mail_candidates, mailbox_index, mailbox_write_pending, maps, mask, occupied, order, order_index, ordinary_intent, outbox_busy, pending_valid, postponed, publication_outstanding, publish_valid, received, request_in, result_out, slot, startup_seen, state_write_pending, used, write_gather_addr, write_gather_mask, write_gather_slot, write_gather_valid, write_gather_value, write_machine_slot, write_machine_valid, write_mailbox_slot, write_mailbox_valid, xls_actor_codegen, xls_collection_codegen, xls_collection_observation, xls_direct_collection_codegen, xls_emitted, xls_exclusive_collection_codegen, xls_gather_codegen, xls_indexed_collection_codegen, xls_indexed_memory_codegen, xls_machine_codegen, xls_machine_layout, xls_machine_names, xls_publication_codegen, xls_reduction_codegen, xls_scheduler_observation, xls_scheduler_ram_dslx, xls_state_projection, xls_statem_codegen, xls_statem_event_codegen, xls_statem_reply_codegen, xls_template | code:priv_dir, file:read_file | apps/hls_lowering/src/backend/xls/scheduler/xls_scheduler_codegen.erl | code, erlang, file, filename, lists, xls_actor_codegen, xls_collection_codegen, xls_collection_observation, xls_direct_collection_codegen, xls_emitted, xls_exclusive_collection_codegen, xls_gather_codegen, xls_indexed_collection_codegen, xls_indexed_memory_codegen, xls_machine_codegen, xls_machine_layout, xls_machine_names, xls_publication_codegen, xls_reduction_codegen, xls_reduction_service_codegen, xls_scheduler_observation, xls_scheduler_ram_dslx, xls_state_projection, xls_statem_codegen, xls_statem_event_codegen, xls_statem_reply_codegen, xls_template |
| apps/hls_lowering/src/backend/xls/scheduler/xls_scheduler_observation.erl | xls_scheduler_observation | hls_lowering | enabled/1 imports/1, proc_field/1, config_parameter/1, config_value/1, sample/1 arguments/1, names/1, spawn_argument/2 wires/1, ports/1 | phi_decoder_profile_top_v, phi_memory_debug_top_v, phi_memory_gateway_dslx, phi_partition_ram, xls_fabric_topology_instance_dslx, xls_fabric_topology_profile, xls_scheduler_actor, xls_scheduler_codegen, xls_scheduler_debug, xls_topology_scheduler_dslx | — | lists, mailbox_debug_out, maps, step | — | apps/hls_lowering/src/backend/xls/scheduler/xls_scheduler_observation.erl | erlang, lists |
| apps/hls_lowering/src/backend/xls/scheduler/xls_scheduler_ram_dslx.erl | xls_scheduler_ram_dslx | hls_lowering | parameters/2, parameters/3, parameters/4 names/1, names/2, names/3 | hls_partition_shared_dslx, phi_decoder_profile_build, phi_memory_gateway_dslx, xls_fabric_topology_instance_dslx, xls_scheduler_codegen, xls_scheduler_ram_v, xls_topology_scheduler_dslx | — | maps, string | — | apps/hls_lowering/src/backend/xls/scheduler/xls_scheduler_ram_dslx.erl | erlang, string |
| apps/hls_lowering/src/backend/xls/scheduler/xls_topology_scheduler_dslx.erl | xls_topology_scheduler_dslx | hls_lowering | emit/1 effect_router/3 | xls_fabric_topology_dslx, xls_fabric_topology_instance_dslx | — | code, credit_out, family, file, filename, frame, lists, maps, scheduled_in, scheduler, slot, spatial_in, window_grant_in, window_release_out, window_request_out, x, xls_effect_window_dslx, xls_names, xls_nums, xls_scheduler_codegen, xls_scheduler_observation, xls_scheduler_ram_dslx, xls_template, xls_topology_ingress, xls_topology_scheduler_plan, xls_topology_source_fragment_dslx, y | code:priv_dir, file:filename, file:read_file | apps/hls_lowering/src/backend/xls/scheduler/xls_topology_scheduler_dslx.erl | code, erlang, file, filename, lists, xls_effect_window_dslx, xls_names, xls_nums, xls_scheduler_codegen, xls_scheduler_observation, xls_scheduler_ram_dslx, xls_template, xls_topology_ingress, xls_topology_scheduler_plan, xls_topology_source_fragment_dslx |
| apps/hls_lowering/src/backend/xls/scheduler/xls_topology_source_fragment_dslx.erl | xls_topology_source_fragment_dslx | hls_lowering | router_arguments/2, router_argument_names/2, router_state_bindings/2, router_batch_bindings/2, router_send/2, router_index_step/2, router_spawn_arguments/2 support/1, plane_channels/1, plane_spawns/1, aggregate_mux_spawns/1 scheduler_channels/2, scheduler_service_argument/2 | xls_topology_scheduler_dslx | — | batch_in, code, file, filename, frames, lists, maps, slot, source, string, xls_names, xls_nums, xls_template | code:priv_dir, file:read_file | apps/hls_lowering/src/backend/xls/scheduler/xls_topology_source_fragment_dslx.erl | code, erlang, file, filename, lists, string, xls_names, xls_nums, xls_template |
| apps/hls_lowering/src/backend/xls/xls_template.erl | xls_template | hls_lowering | render/2 | xls_activation_codegen, xls_direct_collection_codegen, xls_local_owner, xls_parallel_effect_router_dslx, xls_protocol_boundary, xls_protocol_bridge, xls_protocol_inbox, xls_protocol_network, xls_protocol_transport, xls_scheduler_codegen, xls_topology_scheduler_dslx, xls_topology_source_fragment_dslx | — | binary, lists, re | — | apps/hls_lowering/src/backend/xls/xls_template.erl | binary, erlang, lists, re |
| apps/hls_lowering/src/examples/counter/hls_counter_example.erl | hls_counter_example | hls_lowering | init/1, counting/3 topology/0 | — | behaviour hls_statem, compile {parse_transform, hls_pack} | hls_nums, hls_statem, hls_topology, hls_type | — | apps/hls_lowering/src/examples/counter/hls_counter_example.erl | erlang, hls_gs, hls_nums, hls_type |
| apps/hls_lowering/src/planning/hls_host_codec_plan.erl | hls_host_codec_plan | hls_lowering | schemas/1, outputs/1 | hls_node_topology, hls_partition, hls_protocol_application_binding | — | hls_actor_interface, hls_host_codec, hls_record_codec, lists, maps | — | apps/hls_lowering/src/planning/hls_host_codec_plan.erl | erlang, hls_actor_interface, hls_record_codec, lists, maps |
| apps/hls_lowering/src/planning/hls_partition_binding.erl | hls_partition_binding | hls_lowering | deployment/1, binding/4 | hls_protocol_application_binding | — | crypto, hls_partition, lists, maps | — | apps/hls_lowering/src/planning/hls_partition_binding.erl | crypto, erlang, hls_partition, lists, maps |
| apps/hls_lowering/src/planning/partition/hls_partition.erl | hls_partition | hls_lowering | normalize/2, normalize/3, device/2 | hls_partition_binding, hls_partition_dslx | — | hls_actor_interface, hls_codec, hls_frame_layout, hls_host_codec_plan, hls_partition_ingress_plan, hls_partition_reduction, hls_partition_schedule, hls_partition_tile, hls_topology, hls_type, lists, maps, xls_fabric_topology_profile | — | apps/hls_lowering/src/planning/partition/hls_partition.erl | erlang, hls_actor_interface, hls_codec, hls_frame_layout, hls_host_codec_plan, hls_partition_ingress_plan, hls_partition_schedule, hls_partition_tile, hls_topology, hls_type, lists, maps, xls_fabric_topology_profile |
| apps/hls_lowering/src/planning/partition/hls_partition_ingress_plan.erl | hls_partition_ingress_plan | hls_lowering | lower/3 | hls_partition | — | hls_topology, lists, maps, xls_topology_ingress | — | apps/hls_lowering/src/planning/partition/hls_partition_ingress_plan.erl | erlang, lists, maps, xls_topology_ingress |
| apps/hls_lowering/src/planning/partition/hls_partition_reduction.erl | hls_partition_reduction | hls_lowering | attach/3, requirements/1 inputs/2, group/2, queue_extra/2 | hls_partition, hls_partition_dslx, hls_partition_links, hls_partition_outbox, hls_partition_reduction_dslx | — | hls_frame_layout, hls_reduction_plan, hls_scheduler_plan, hls_topology, lists, maps | — | apps/hls_lowering/src/planning/partition/hls_partition_reduction.erl | erlang, hls_frame_layout, hls_reduction_plan, hls_scheduler_plan, lists, maps |
| apps/hls_lowering/src/planning/partition/hls_partition_schedule.erl | hls_partition_schedule | hls_lowering | shared/2, shared_by_module/2, shared_by_module/3 local/2, topology/1, specs/1 | hls_partition, hls_partition_tile | — | hls_frame_layout, hls_scheduler_plan, lists, maps | — | apps/hls_lowering/src/planning/partition/hls_partition_schedule.erl | erlang, hls_frame_layout, hls_scheduler_plan, lists, maps |
| apps/hls_lowering/src/planning/partition/hls_partition_tile_debug.erl | hls_partition_tile_debug | hls_lowering | prepare/3 catalog/3 | — | — | hls_frame_layout, hls_partition_tile, hls_scheduler_plan, hls_shared_debug_catalog, hls_shared_observation, lists, maps | — | apps/hls_lowering/src/planning/partition/hls_partition_tile_debug.erl | erlang, hls_frame_layout, hls_partition_tile, hls_scheduler_plan, hls_shared_debug_catalog, hls_shared_observation, lists, maps |
| apps/hls_lowering/src/planning/protocol/hls_protocol_application_binding.erl | hls_protocol_application_binding | hls_lowering | bind/4 | hls_protocol_application, hls_protocol_deployment, hls_protocol_mixed | — | hls_actor_interface, hls_frame_layout, hls_host_codec_plan, hls_local_actor, hls_partition_binding, hls_protocol_application_schema, hls_protocol_control, hls_protocol_schema, hls_protocol_topology, hls_protocol_transport, hls_records, hls_source_config, lists, maps, xls_actor_program, xls_statem_plan | — | apps/hls_lowering/src/planning/protocol/hls_protocol_application_binding.erl | erlang, hls_actor_interface, hls_host_codec_plan, hls_partition_binding, hls_protocol_control, hls_protocol_schema, hls_records, lists, maps, xls_actor_program, xls_statem_plan |
| apps/hls_lowering/src/planning/protocol/hls_protocol_arithmetic.erl | hls_protocol_arithmetic | hls_lowering | plan/3, select/3 | hls_protocol_transport, xls_protocol_network | — | hls_diagnostic, hls_local_actor, lists, maps, xls_actor_program | — | apps/hls_lowering/src/planning/protocol/hls_protocol_arithmetic.erl | erlang, hls_diagnostic, lists, maps, xls_actor_program |
| apps/hls_lowering/src/planning/protocol/hls_protocol_capture.erl | hls_protocol_capture | hls_lowering | plan/2 | hls_protocol_inbox, hls_protocol_partition, hls_protocol_source, hls_protocol_transactions, hls_protocol_transport, xls_protocol_network | — | binary, crypto, file, hls_frame_layout, hls_protocol_topology, hls_type, lists, maps, xls_actor_program, xls_statem_plan | file:filename | apps/hls_lowering/src/planning/protocol/hls_protocol_capture.erl | binary, crypto, erlang, hls_frame_layout, hls_type, lists, maps, xls_actor_program, xls_statem_plan |
| apps/hls_lowering/src/planning/protocol/hls_protocol_codec_plan.erl | hls_protocol_codec_plan | hls_lowering | plan/2, plan/3 | hls_protocol_inbox, hls_protocol_partition, hls_protocol_source | — | hls_codec, hls_frame_layout, hls_protocol_codec, hls_type, lists, maps, xls_message_bits | — | apps/hls_lowering/src/planning/protocol/hls_protocol_codec_plan.erl | erlang, hls_codec, hls_frame_layout, hls_type, lists, maps, xls_message_bits |
| apps/hls_lowering/src/planning/protocol/hls_protocol_control.erl | hls_protocol_control | hls_lowering | plan/1, addressed/2, project/2, host_ingresses/2 ports/1, framed/2, check_boundary/2 | hls_protocol_application, hls_protocol_application_binding, hls_protocol_bridge, hls_protocol_partition, hls_protocol_transport, xls_protocol_bridge, xls_protocol_network | — | hls_diagnostic, hls_frame_layout, hls_local_actor, hls_protocol_schema, hls_protocol_topology, lists, maps | — | apps/hls_lowering/src/planning/protocol/hls_protocol_control.erl | erlang, hls_diagnostic, hls_frame_layout, hls_protocol_schema, lists, maps |
| apps/hls_lowering/src/planning/protocol/hls_protocol_fabric.erl | hls_protocol_fabric | hls_lowering | plan/2 | hls_protocol_inbox, hls_protocol_partition, hls_protocol_transport, xls_protocol_network, xls_protocol_partition, xls_protocol_transport | — | hls_frame_layout, hls_protocol_inbox, hls_protocol_link, hls_protocol_partition, hls_protocol_source, lists, maps, math | — | apps/hls_lowering/src/planning/protocol/hls_protocol_fabric.erl | erlang, hls_frame_layout, hls_protocol_link, lists, math |
| apps/hls_lowering/src/planning/protocol/hls_protocol_identity.erl | hls_protocol_identity | hls_lowering | source_modules/1, boundary/2 | hls_protocol_application, hls_protocol_bridge, hls_protocol_inspection | — | filename, hls_generated_files, hls_local_actor, lists, maps, xls_actor_program, xls_statem_plan | — | apps/hls_lowering/src/planning/protocol/hls_protocol_identity.erl | erlang, filename, hls_generated_files, lists, maps, xls_actor_program, xls_statem_plan |
| apps/hls_lowering/src/planning/protocol/hls_protocol_inbox.erl | hls_protocol_inbox | hls_lowering | plan/1, plan/5 descriptor/1, completion/1, link_bindings/1 | hls_local_actor, hls_protocol_fabric, hls_protocol_source, hls_protocol_transport, xls_protocol_inbox, xls_protocol_network | — | hls_frame_layout, hls_local_actor, hls_protocol_capture, hls_protocol_codec, hls_protocol_codec_plan, hls_protocol_fabric, hls_protocol_schema, lists, maps, math, xls_actor_program, xls_protocol_inbox | — | apps/hls_lowering/src/planning/protocol/hls_protocol_inbox.erl | erlang, hls_frame_layout, hls_local_actor, hls_protocol_codec_plan, hls_protocol_schema, lists, maps, math, xls_actor_program |
| apps/hls_lowering/src/planning/protocol/hls_protocol_inventory.erl | hls_protocol_inventory | hls_lowering | inspect/2 | hls_protocol_model, hls_protocol_transport, phi_protocol_model | — | binary, crypto, erl_anno, hls_topology, lists, maps, xls_actor_program, xls_statem_plan | — | apps/hls_lowering/src/planning/protocol/hls_protocol_inventory.erl | binary, crypto, erl_anno, erlang, lists, maps, xls_actor_program, xls_statem_plan |
| apps/hls_lowering/src/planning/protocol/hls_protocol_link.erl | hls_protocol_link | hls_lowering | components/1 | hls_protocol_fabric | — | lists | — | apps/hls_lowering/src/planning/protocol/hls_protocol_link.erl | erlang, lists |
| apps/hls_lowering/src/planning/protocol/hls_protocol_model.erl | hls_protocol_model | hls_lowering | check/2 emit/1, write/2 | hls_protocol_transport, hls_source_config, phi_protocol_config, phi_protocol_model, xls_protocol_network | — | binary, crypto, file, hls_diagnostic, hls_generated_files, hls_protocol_inventory, hls_protocol_wait_graph, json, maps | file:filename | apps/hls_lowering/src/planning/protocol/hls_protocol_model.erl | binary, crypto, erlang, hls_diagnostic, hls_generated_files, hls_protocol_wait_graph, json, maps |
| apps/hls_lowering/src/planning/protocol/hls_protocol_partition.erl | hls_protocol_partition | hls_lowering | plan/5 | hls_protocol_bridge, hls_protocol_fabric, hls_protocol_mixed, hls_protocol_transport, xls_protocol_bridge, xls_protocol_network, xls_protocol_partition | — | hls_diagnostic, hls_protocol_capture, hls_protocol_codec, hls_protocol_codec_plan, hls_protocol_control, hls_protocol_fabric, hls_protocol_topology, hls_protocol_transport, lists, maps, placement, xls_actor_program | — | apps/hls_lowering/src/planning/protocol/hls_protocol_partition.erl | erlang, hls_diagnostic, hls_protocol_codec_plan, hls_protocol_control, lists, maps, xls_actor_program |
| apps/hls_lowering/src/planning/protocol/hls_protocol_projection.erl | hls_protocol_projection | hls_lowering | plan/1, frame/2, frame/3 evaluate/2 | hls_protocol_source, xls_protocol_bits, xls_protocol_transport | — | hls_codec, hls_frame_layout, hls_type, lists, maps, xls_type | — | apps/hls_lowering/src/planning/protocol/hls_protocol_projection.erl | erlang, hls_codec, hls_frame_layout, hls_type, lists, maps, xls_type |
| apps/hls_lowering/src/planning/protocol/hls_protocol_schema.erl | hls_protocol_schema | hls_lowering | frames/2, domains/2 | hls_protocol_application_binding, hls_protocol_control, hls_protocol_inbox | — | binary, crypto, hls_diagnostic, hls_frame_layout, hls_local_actor, hls_type, lists, maps, re, xls_actor_program, xls_message_bits, xls_statem_plan, xls_type | — | apps/hls_lowering/src/planning/protocol/hls_protocol_schema.erl | binary, crypto, erlang, hls_diagnostic, hls_frame_layout, hls_type, lists, maps, re, xls_actor_program, xls_message_bits, xls_statem_plan, xls_type |
| apps/hls_lowering/src/planning/protocol/hls_protocol_source.erl | hls_protocol_source | hls_lowering | plan/3 | hls_protocol_fabric, hls_protocol_transport, xls_protocol_network, xls_protocol_transport | — | hls_frame_layout, hls_local_actor, hls_protocol_capture, hls_protocol_codec_plan, hls_protocol_inbox, hls_protocol_projection, hls_protocol_topology, hls_protocol_transactions, lists, maps, xls_actor_codegen, xls_actor_program | — | apps/hls_lowering/src/planning/protocol/hls_protocol_source.erl | erlang, hls_frame_layout, hls_protocol_codec_plan, hls_protocol_inbox, hls_protocol_projection, lists, maps, xls_actor_program |
| apps/hls_lowering/src/planning/protocol/hls_protocol_topology.erl | hls_protocol_topology | hls_lowering | elaborate/2 | hls_build_profile, hls_protocol_application_binding, hls_protocol_capture, hls_protocol_control, hls_protocol_deployment, hls_protocol_mixed, hls_protocol_partition, hls_protocol_source, hls_protocol_transactions, hls_protocol_transport, hls_source_config, xls_protocol_network | — | hls_diagnostic, hls_topology, identity, lists, maps, xls_topology_graph | — | apps/hls_lowering/src/planning/protocol/hls_protocol_topology.erl | erlang, hls_diagnostic, hls_topology, lists, maps, xls_topology_graph |
| apps/hls_lowering/src/planning/protocol/hls_protocol_transactions.erl | hls_protocol_transactions | hls_lowering | plan/2 | hls_protocol_source, hls_protocol_transport, xls_protocol_network | — | hls_protocol_capture, hls_protocol_topology, hls_type, lists, maps, xls_actor_program | — | apps/hls_lowering/src/planning/protocol/hls_protocol_transactions.erl | erlang, hls_type, lists, maps |
| apps/hls_lowering/src/planning/protocol/hls_protocol_wait_graph.erl | hls_protocol_wait_graph | hls_lowering | check/2 | hls_protocol_model | — | digraph, digraph_utils, lists, maps | — | apps/hls_lowering/src/planning/protocol/hls_protocol_wait_graph.erl | digraph, digraph_utils, erlang, lists, maps |
| apps/hls_lowering/src/planning/scheduler/hls_node_topology.erl | hls_node_topology | hls_lowering | normalize/3 bind_debug/4 | — | — | hls_actor_interface, hls_host_codec_plan, hls_scheduler_plan, hls_shared_debug_catalog, hls_shared_observation, hls_topology, hls_type, lists, maps | — | apps/hls_lowering/src/planning/scheduler/hls_node_topology.erl | erlang, hls_actor_interface, hls_host_codec_plan, hls_scheduler_plan, hls_shared_debug_catalog, hls_shared_observation, hls_type, lists, maps |
| apps/hls_lowering/src/planning/scheduler/hls_reduction_plan.erl | hls_reduction_plan | hls_lowering | normalize/3, normalize/4 artifact_requirements/1 | hls_partition_reduction, xls_fabric_topology_family_dslx | — | erlang, hls_actor_interface, hls_scheduler_plan, hls_topology, lists, maps | — | apps/hls_lowering/src/planning/scheduler/hls_reduction_plan.erl | erlang, hls_actor_interface, lists, maps |
| apps/hls_lowering/src/planning/scheduler/hls_scheduler_plan.erl | hls_scheduler_plan | hls_lowering | interfaces/2, normalize/2, normalize/3, normalize/4 placements/1 | hls_node_topology, hls_partition_reduction, hls_partition_schedule, hls_partition_tile_debug, hls_reduction_plan, hls_scheduler_build, hls_shared_debug_catalog, hls_topology_constants, phi_decoder_profile_top_v, phi_decoder_profile_topology_dslx, phi_partition_ram, phi_shared_noise_topology_dslx, snowflake_actor_topology, xls_fabric_topology_dslx, xls_fabric_topology_family_dslx, xls_fabric_topology_instance_dslx, xls_scheduler_debug, xls_scheduler_ram_v | — | hints, hls_actor_interface, hls_frame_layout, hls_topology, hls_topology_constants, lists, maps, xls_gather_codegen | — | apps/hls_lowering/src/planning/scheduler/hls_scheduler_plan.erl | erlang, hls_actor_interface, hls_frame_layout, hls_topology_constants, lists, maps, xls_gather_codegen |
| apps/hls_lowering/src/planning/scheduler/hls_shared_debug_catalog.erl | hls_shared_debug_catalog | hls_lowering | prepare/4 hardware/3, hardware/4 | hls_node_topology, hls_partition_tile_debug | — | hls_debug_catalog, hls_frame_layout, hls_scheduler_plan, hls_shared_observation, hls_topology, maps, xls_scheduler_debug | — | apps/hls_lowering/src/planning/scheduler/hls_shared_debug_catalog.erl | erlang, hls_debug_catalog, hls_frame_layout, hls_scheduler_plan, hls_shared_observation, xls_scheduler_debug |
| apps/hls_lowering/src/planning/scheduler/hls_topology_constants.erl | hls_topology_constants | hls_lowering | specialize/2, specialize/3, specialize/4 requirements/2 | hls_scheduler_plan, xls_fabric_topology_instance_dslx | — | binary, crypto, hls_actor_constants, hls_actor_interface, hls_frame_layout, hls_records, hls_scheduler_plan, hls_source, hls_topology, hls_type, lists, maps, proplists, xls_parse | — | apps/hls_lowering/src/planning/scheduler/hls_topology_constants.erl | binary, crypto, erlang, hls_actor_constants, hls_actor_interface, hls_frame_layout, hls_records, hls_scheduler_plan, hls_source, hls_type, lists, maps, proplists, xls_parse |
| apps/hls_lowering/src/planning/scheduler/xls_fabric_topology_family_dslx.erl | xls_fabric_topology_family_dslx | hls_lowering | lower/4 | xls_fabric_topology_dslx | — | hls_actor_interface, hls_reduction_plan, hls_scheduler_plan, hls_topology, lists, maps, xls_fabric_topology_profile, xls_topology_family_dslx | — | apps/hls_lowering/src/planning/scheduler/xls_fabric_topology_family_dslx.erl | erlang, hls_reduction_plan, lists, maps, xls_fabric_topology_profile, xls_topology_family_dslx |
| apps/hls_lowering/src/planning/scheduler/xls_fabric_topology_profile.erl | xls_fabric_topology_profile | hls_lowering | normalize/1 identifier/2, egress_depth/2 | hls_build_profile, hls_partition, hls_partition_dslx, hls_scheduler_build, xls_fabric_topology_dslx, xls_fabric_topology_family_dslx, xls_fabric_topology_instance_dslx, xls_scheduler_debug | — | hls_actor_interface, hls_frame_layout, lists, maps, re, xls_actor_observation, xls_names, xls_scheduler_observation | — | apps/hls_lowering/src/planning/scheduler/xls_fabric_topology_profile.erl | erlang, hls_actor_interface, hls_frame_layout, lists, maps, re, xls_actor_observation, xls_names, xls_scheduler_observation |
| apps/hls_lowering/src/planning/scheduler/xls_scheduler_debug.erl | xls_scheduler_debug | hls_lowering | projection/2, projection/3, projection/4 validate/3 | hls_shared_debug_catalog, phi_decoder_profile_build, phi_partition_ram, snowflake_actor_topology | — | hls_actor_identity, hls_actor_interface, hls_frame_layout, hls_scheduler_plan, hls_topology, io_lib, json, lists, maps, xls_actor_debug, xls_actor_observation, xls_collection_observation, xls_emitted, xls_fabric_topology_dslx, xls_fabric_topology_profile, xls_failure_sites, xls_machine_layout, xls_scheduler_observation, xls_state_projection, xls_statem_reduction_ir | — | apps/hls_lowering/src/planning/scheduler/xls_scheduler_debug.erl | erlang, hls_actor_identity, hls_frame_layout, hls_scheduler_plan, io_lib, json, lists, maps, xls_actor_debug, xls_actor_observation, xls_collection_observation, xls_emitted, xls_fabric_topology_dslx, xls_failure_sites, xls_machine_layout, xls_scheduler_observation, xls_state_projection, xls_statem_reduction_ir |
| apps/hls_lowering/src/planning/scheduler/xls_topology_effect_windows.erl | xls_topology_effect_windows | hls_lowering | partition/3, annotate/2 | xls_fabric_topology_instance_dslx, xls_topology_scheduler_plan | — | lists, maps | — | apps/hls_lowering/src/planning/scheduler/xls_topology_effect_windows.erl | erlang, lists, maps |
| apps/hls_lowering/src/planning/scheduler/xls_topology_scheduler_plan.erl | xls_topology_scheduler_plan | hls_lowering | prepare/1 descriptor/1, graph/1, artifact_requirements/1 | xls_fabric_topology_dslx, xls_topology_scheduler_dslx | — | hls_codec, hls_type, lists, maps, xls_topology_effect_windows | — | apps/hls_lowering/src/planning/scheduler/xls_topology_scheduler_plan.erl | erlang, hls_codec, hls_type, lists, maps, xls_topology_effect_windows |
| apps/hls_lowering/src/planning/xls_machine_layout.erl | xls_machine_layout | hls_lowering | new/1, from_spec/1, from_group/1 width/1, field/2, fields/1 | hls_local_actor, xls_collection_codegen, xls_exclusive_collection_codegen, xls_machine_codegen, xls_scheduler_codegen, xls_scheduler_debug, xls_scheduler_ram_v | — | hls_bits, hls_field_layout, hls_nums, hls_type, maps, xls_gather_codegen, xls_state_projection, xls_statem_reduction_codegen, xls_statem_reply_codegen | — | apps/hls_lowering/src/planning/xls_machine_layout.erl | erlang, hls_bits, hls_field_layout, hls_nums, maps, xls_gather_codegen, xls_state_projection, xls_statem_reduction_codegen, xls_statem_reply_codegen |
| apps/hls_lowering/src/toolchain/hls_build.erl | hls_build | hls_lowering | plan/1, inspect/2, descriptor/1 write/2 | hls_fabric_cli, phi_protocol_cli | — | file, hls_diagnostic, hls_scheduler_build, hls_source_build, hls_source_config, lists, maps | file:filename | apps/hls_lowering/src/toolchain/hls_build.erl | erlang, hls_diagnostic, hls_scheduler_build, hls_source_build, hls_source_config, lists, maps |
| apps/hls_lowering/src/toolchain/hls_build_profile.erl | hls_build_profile | hls_lowering | protocol/2, owner/0, owner/1 scheduler/2, scheduler/3, experiment/1 flags/2 | hls_fabric_cli, hls_local_actor, hls_scheduler_build, hls_source_build, phi_decoder_profile_build | — | hls_diagnostic, hls_frame_layout, hls_protocol_topology, hls_source_build, hls_source_config, lists, maps, re, unicode, xls_fabric_topology_profile | — | apps/hls_lowering/src/toolchain/hls_build_profile.erl | erlang, hls_diagnostic, hls_frame_layout, hls_source_config, lists, maps, re, unicode, xls_fabric_topology_profile |
| apps/hls_lowering/src/toolchain/hls_build_sources.erl | hls_build_sources | hls_lowering | load/2 | hls_protocol_transport, hls_scheduler_build | — | code, compile, erl_anno, erlang, file, hls_diagnostic, hls_source, lists, unicode | file:filename | apps/hls_lowering/src/toolchain/hls_build_sources.erl | code, compile, erlang, hls_diagnostic, lists, unicode |
| apps/hls_lowering/src/toolchain/hls_build_support.erl | hls_build_support | hls_lowering | layout/1 | hls_scheduler_build, hls_source_build | — | code, file, filelib, filename, hls_artifact_bundle, hls_compile, unicode | code:priv_dir, file:filename | apps/hls_lowering/src/toolchain/hls_build_support.erl | code, erlang, filelib, filename, hls_compile, unicode |
| apps/hls_lowering/src/toolchain/hls_fabric_cli.erl | hls_fabric_cli | hls_lowering | main/0, run/1 | — | — | file, filelib, hls_build, hls_build_profile, hls_cli, hls_diagnostic, hls_source_build, io, json, kinds, maps, unicode | file:filename, file:format_error, file:write_file | apps/hls_lowering/src/toolchain/hls_fabric_cli.erl | erlang, file, filelib, hls_build, hls_build_profile, hls_cli, hls_diagnostic, io, json, unicode |
| apps/hls_lowering/src/toolchain/hls_generated_files.erl | hls_generated_files | hls_lowering | merge/1, prefix/2, hash/1 write/2, write_into/2 | hls_local_actor, hls_protocol_application, hls_protocol_boundary, hls_protocol_bridge, hls_protocol_deployment, hls_protocol_identity, hls_protocol_inspection, hls_protocol_mixed, hls_protocol_model, hls_protocol_network, hls_protocol_transport, hls_scheduler_build, hls_source_build, phi_decoder_profile_build, xls_protocol_application, xls_protocol_boundary, xls_protocol_bridge, xls_protocol_network, xls_protocol_partition, xls_protocol_transport | — | binary, crypto, file, filelib, filename, lists, maps, string | file:filename, file:make_dir, file:write_file | apps/hls_lowering/src/toolchain/hls_generated_files.erl | binary, crypto, erlang, file, filelib, filename, lists, maps, string |
| apps/hls_lowering/src/toolchain/hls_scheduler_build.erl | hls_scheduler_build | hls_lowering | plan/1, descriptor/1, inspect/2 write/2 | hls_build | — | binary, erlang, file, filename, hls_artifact_bundle, hls_build_profile, hls_build_sources, hls_build_support, hls_compile, hls_diagnostic, hls_frame_layout, hls_generated_files, hls_scheduler_plan, hls_source, hls_source_config, hls_topology, io_lib, json, lists, maps, proplists, unicode, xls_emitted, xls_fabric_topology_dslx, xls_fabric_topology_profile, xls_scheduler_actor, xls_scheduler_ram_v | apply, file:filename, file:get_cwd | apps/hls_lowering/src/toolchain/hls_scheduler_build.erl | binary, erlang, file, filename, hls_artifact_bundle, hls_build_profile, hls_build_sources, hls_build_support, hls_compile, hls_diagnostic, hls_frame_layout, hls_generated_files, hls_source_config, hls_topology, io_lib, json, lists, maps, proplists, unicode, xls_emitted, xls_fabric_topology_dslx, xls_fabric_topology_profile, xls_scheduler_actor, xls_scheduler_ram_v |
| apps/hls_lowering/src/toolchain/hls_source_build.erl | hls_source_build | hls_lowering | plan/2, descriptor/1, inspect/2 write/2, write/3 | hls_build, hls_build_profile, hls_fabric_cli, hls_source_config, phi_protocol_config | — | code, file, filelib, filename, hls_artifact_bundle, hls_build_profile, hls_build_support, hls_compile, hls_diagnostic, hls_frame_layout, hls_generated_files, hls_local_actor, hls_protocol_application, hls_protocol_boundary, hls_protocol_bridge, hls_protocol_deployment, hls_protocol_mixed, hls_protocol_network, hls_protocol_transport, hls_source_config, io_lib, lists, maps, unicode | file:filename, file:format_error, file:get_cwd, file:read_link_info, file:write_file | apps/hls_lowering/src/toolchain/hls_source_build.erl | code, erlang, file, filelib, filename, hls_artifact_bundle, hls_build_profile, hls_build_support, hls_compile, hls_diagnostic, hls_frame_layout, hls_generated_files, hls_local_actor, hls_protocol_boundary, hls_protocol_bridge, hls_protocol_deployment, hls_protocol_network, hls_protocol_transport, hls_source_config, io_lib, lists, maps, unicode |
| apps/hls_lowering/src/toolchain/hls_source_config.erl | hls_source_config | hls_lowering | read/1 validate/2, validate_source/1 | hls_build, hls_build_profile, hls_protocol_application, hls_protocol_application_binding, hls_protocol_boundary, hls_protocol_bridge, hls_protocol_deployment, hls_protocol_mixed, hls_protocol_network, hls_protocol_transport, hls_scheduler_build, hls_source_build, snowflake_source | — | binary, file, filename, hls_diagnostic, hls_frame_layout, hls_protocol_model, hls_protocol_topology, hls_source, hls_source_build, lists, maps, unicode | file:consult, file:filename, file:format_error | apps/hls_lowering/src/toolchain/hls_source_config.erl | binary, erlang, file, filename, hls_diagnostic, hls_frame_layout, lists, maps, unicode |
| apps/hls_phi/src/hls_pauli.erl | hls_pauli | hls_phi | pauli/0, i/0, x/0, y/0, z/0, multiply/2, anticommutes/2, is_pauli/1 width/2, zero/2, transpile/3, pack/3, unpack/3, print_type/2 | phi_memory_wire, phi_noise_topology, phi_repetition_memory, phi_repetition_topology | behavior hls_type | xls_clause_lower | — | apps/hls_phi/src/hls_pauli.erl | erlang, xls_clause_lower |
| apps/hls_phi/src/phenom_data_cell.erl | phenom_data_cell | hls_phi | — | — | include "../include/phenom_data_cell_impl.hrl" | hls_prng | — | apps/hls_phi/src/phenom_data_cell.erl | erlang, hls_bool, hls_gs, hls_nums, hls_pauli, hls_prng, hls_statem, hls_type, lists, maps, phi_field |
| apps/hls_phi/src/phenom_line_data_cell.erl | phenom_line_data_cell | hls_phi | — | — | include "../include/phenom_data_cell_impl.hrl" | — | — | apps/hls_phi/src/phenom_line_data_cell.erl | erlang, hls_bool, hls_gs, hls_nums, hls_pauli, hls_prng, hls_statem, hls_type, lists, maps, phi_field |
| apps/hls_phi/src/phenom_line_syndrome_cell.erl | phenom_line_syndrome_cell | hls_phi | — | — | include "../include/phenom_syndrome_cell_impl.hrl" | — | — | apps/hls_phi/src/phenom_line_syndrome_cell.erl | erlang, hls_bool, hls_gs, hls_nums, hls_pauli, hls_prng, hls_statem, hls_type, lists, maps, phi_field |
| apps/hls_phi/src/phenom_syndrome_cell.erl | phenom_syndrome_cell | hls_phi | — | — | include "../include/phenom_syndrome_cell_impl.hrl" | recipient | — | apps/hls_phi/src/phenom_syndrome_cell.erl | erlang, hls_bool, hls_gs, hls_nums, hls_pauli, hls_prng, hls_statem, hls_type, lists, maps, phi_field |
| apps/hls_phi/src/phi_decoder_profile.erl | phi_decoder_profile | hls_phi | normalize/1, planes/1 manifest/1 | phi_decoder_profile_build, phi_decoder_profile_top_v, phi_decoder_profile_topology, phi_decoder_profile_topology_dslx | — | lists, maps | — | apps/hls_phi/src/phi_decoder_profile.erl | erlang, lists, maps |
| apps/hls_phi/src/phi_decoder_profile_build.erl | phi_decoder_profile_build | hls_phi | emit/2 | — | — | code, filename, hls_build_profile, hls_diagnostic, hls_frame_layout, hls_generated_files, hls_topology, json, lists, maps, phi_decoder_profile, phi_decoder_profile_top_v, phi_decoder_profile_topology, phi_decoder_profile_topology_dslx, unicode, xls_emitted, xls_fabric_topology_dslx, xls_scheduler_actor, xls_scheduler_debug, xls_scheduler_ram_dslx, xls_scheduler_ram_v | — | apps/hls_phi/src/phi_decoder_profile_build.erl | code, erlang, filename, hls_build_profile, hls_diagnostic, hls_frame_layout, hls_generated_files, hls_topology, json, lists, maps, phi_decoder_profile, phi_decoder_profile_top_v, phi_decoder_profile_topology, phi_decoder_profile_topology_dslx, unicode, xls_emitted, xls_fabric_topology_dslx, xls_scheduler_actor, xls_scheduler_debug, xls_scheduler_ram_dslx, xls_scheduler_ram_v |
| apps/hls_phi/src/phi_decoder_profile_top_v.erl | phi_decoder_profile_top_v | hls_phi | to_verilog/0, to_verilog/1, to_verilog/2 emit/3, emit/4 | phi_decoder_profile_build | — | binary, code, file, filename, hls_scheduler_plan, io_lib, lists, phi_decoder_profile, phi_decoder_profile_topology_dslx, xls_scheduler_observation, xls_scheduler_ram_v | code:priv_dir, file:read_file | apps/hls_phi/src/phi_decoder_profile_top_v.erl | binary, code, erlang, file, filename, io_lib, lists, phi_decoder_profile, phi_decoder_profile_topology_dslx, xls_scheduler_observation, xls_scheduler_ram_v |
| apps/hls_phi/src/phi_decoder_profile_topology.erl | phi_decoder_profile_topology | hls_phi | topology/0, topology/1 | phi_decoder_profile_build, phi_decoder_profile_topology_dslx | include "../include/phi_protocol.hrl" | hls_topology, lists, maps, phi_decoder_profile | — | apps/hls_phi/src/phi_decoder_profile_topology.erl | erlang, lists, maps, phi_decoder_profile |
| apps/hls_phi/src/phi_decoder_profile_topology_dslx.erl | phi_decoder_profile_topology_dslx | hls_phi | profile/0, profile/1, scheduler_plan/0, scheduler_plan/1 to_dslx/0, to_dslx/1 | phi_decoder_profile_build, phi_decoder_profile_top_v | — | hls_scheduler_plan, hls_topology, lists, maps, phi_decoder_profile, phi_decoder_profile_topology, xls_fabric_topology_dslx | — | apps/hls_phi/src/phi_decoder_profile_topology_dslx.erl | erlang, hls_scheduler_plan, hls_topology, lists, maps, phi_decoder_profile, phi_decoder_profile_topology, xls_fabric_topology_dslx |
| apps/hls_phi/src/phi_field.erl | phi_field | hls_phi | scalar/0, field/0, from_integer/1, from_ratio/2, to_float/1, accumulate/2, relax/4, relax_center/4, relax_bulk/3, relax_line/4 width/2, zero/2, transpile/3, pack/3, unpack/3, print_type/2, dslx_imports/0 | — | behavior hls_type | hls_fixed, hls_nums, hls_type, hls_vec, layers, xls_clause_lower, zero | — | apps/hls_phi/src/phi_field.erl | erlang, hls_fixed, hls_nums, hls_type, hls_vec, xls_clause_lower |
| apps/hls_phi/src/phi_halo_cell.erl | phi_halo_cell | hls_phi | — | — | include "../include/phi_halo_cell_impl.hrl" | aware | — | apps/hls_phi/src/phi_halo_cell.erl | erlang, hls_gs, hls_nums, hls_pauli, hls_prng, hls_statem, hls_type, lists, maps, phi_field |
| apps/hls_phi/src/phi_line_cell.erl | phi_line_cell | hls_phi | — | — | include "../include/phi_halo_cell_impl.hrl" | — | — | apps/hls_phi/src/phi_line_cell.erl | erlang, hls_gs, hls_nums, hls_pauli, hls_prng, hls_statem, hls_type, lists, maps, phi_field |
| apps/hls_phi/src/phi_memory_boundary.erl | phi_memory_boundary | hls_phi | contract/1, version/0 | phi_memory_cpu_fabric, phi_memory_gateway_dslx, phi_memory_runner, phi_memory_wire | — | hls_topology, lists, maps, phi_memory_experiment, phi_noise_topology, supply | — | apps/hls_phi/src/phi_memory_boundary.erl | erlang, lists, phi_noise_topology |
| apps/hls_phi/src/phi_memory_cpu_fabric.erl | phi_memory_cpu_fabric | hls_phi | start_link/2, stop/1, debug_targets/1 init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2 | phi_memory_demo | behavior gen_server, include "../include/phi_protocol.hrl" | acknowledgments, authoritative, erlang, gen_server, hls_debug_catalog, hls_nums, hls_statem, hls_topology, lists, maps, phi_memory_boundary, phi_memory_experiment, phi_memory_wire, phi_noise_topology | — | apps/hls_phi/src/phi_memory_cpu_fabric.erl | erlang, gen_server, hls_debug_catalog, hls_statem, hls_topology, lists, maps, phi_memory_boundary, phi_memory_wire, phi_noise_topology |
| apps/hls_phi/src/phi_memory_debug_top_v.erl | phi_memory_debug_top_v | hls_phi | to_verilog/0, to_verilog/1, application/2 | — | — | binary, code, file, filename, lists, phi_shared_noise_topology_dslx, xls_scheduler_observation, xls_scheduler_ram_v | code:priv_dir, file:read_file | apps/hls_phi/src/phi_memory_debug_top_v.erl | binary, code, erlang, file, filename, lists, phi_shared_noise_topology_dslx, xls_scheduler_observation, xls_scheduler_ram_v |
| apps/hls_phi/src/phi_memory_demo.erl | phi_memory_demo | hls_phi | fixture/0, run_cpu/0, run_cpu/1 summary/1, verify/1 witness_envelope/1, decode_witness_envelope/1 | — | — | hls_nums, lists, maps, phi_memory_cpu_fabric, phi_memory_experiment, phi_memory_runner, small | — | apps/hls_phi/src/phi_memory_demo.erl | erlang, lists, maps, phi_memory_cpu_fabric, phi_memory_runner |
| apps/hls_phi/src/phi_memory_experiment.erl | phi_memory_experiment | hls_phi | new/1, event/3 | phi_memory_boundary, phi_memory_cpu_fabric, phi_memory_demo, phi_memory_runner, phi_memory_wire | include "../include/phi_protocol.hrl" | evidence, hls_nums, lists, maps, phi_noise_topology | — | apps/hls_phi/src/phi_memory_experiment.erl | erlang, lists, maps, phi_noise_topology |
| apps/hls_phi/src/phi_memory_gateway_dslx.erl | phi_memory_gateway_dslx | hls_phi | to_dslx/0, to_dslx/1, to_dslx/2, to_dslx/3 | — | — | arm_out, armed, boundary_in, bounds, cursor, frame, frame_in, header, lists, maps, op, payload, payload_words, phi_memory_boundary, phi_shared_noise_topology_dslx, rectangle, routed_frame_out, routed_in, routed_out, source, spatial_out, string, target, txid, x0, x1, xls_scheduler_observation, xls_scheduler_ram_dslx, y0, y1 | — | apps/hls_phi/src/phi_memory_gateway_dslx.erl | erlang, lists, phi_memory_boundary, phi_shared_noise_topology_dslx, string, xls_scheduler_observation, xls_scheduler_ram_dslx |
| apps/hls_phi/src/phi_memory_runner.erl | phi_memory_runner | hls_phi | start_link/3, stop/1, await/1 init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2 | phi_memory_demo | behavior gen_server | erlang, gen_server, hls_fabric, lists, phi_memory_boundary, phi_memory_experiment, phi_memory_wire, queue, retry | — | apps/hls_phi/src/phi_memory_runner.erl | erlang, gen_server, hls_fabric, lists, phi_memory_boundary, phi_memory_experiment, phi_memory_wire, queue |
| apps/hls_phi/src/phi_memory_wire.erl | phi_memory_wire | hls_phi | version/0, control_route/1, event_routes/1 encode_command/2, decode_command/4, encode_event/3, decode_event/4 | phi_memory_cpu_fabric, phi_memory_runner | include "../include/phi_protocol.hrl" | hls_pauli, once, phi_memory_boundary, phi_memory_experiment | — | apps/hls_phi/src/phi_memory_wire.erl | erlang, hls_pauli, phi_memory_boundary |
| apps/hls_phi/src/phi_noise_topology.erl | phi_noise_topology | hls_phi | topology/0, topology/1, topology/2, correction_update/3 | phi_memory_boundary, phi_memory_cpu_fabric, phi_memory_experiment, phi_noise_topology_dslx, phi_shared_noise_topology_dslx | include "../include/phi_protocol.hrl" | hls_nums, hls_pauli, hls_topology, lists | — | apps/hls_phi/src/phi_noise_topology.erl | erlang, hls_pauli, lists |
| apps/hls_phi/src/phi_noise_topology_dslx.erl | phi_noise_topology_dslx | hls_phi | profile/0 to_dslx/0, to_dslx/1, to_dslx/2 | — | — | hls_nums, hls_topology, phi_noise_topology, xls_topology_dslx | — | apps/hls_phi/src/phi_noise_topology_dslx.erl | erlang, hls_topology, phi_noise_topology, xls_topology_dslx |
| apps/hls_phi/src/phi_partition_ram.erl | phi_partition_ram | hls_phi | write/4 | — | — | file, filename, hls_frame_layout, hls_partition_links, hls_partition_tile, hls_scheduler_plan, io_lib, json, lists, maps, xls_emitted, xls_scheduler_debug, xls_scheduler_observation, xls_scheduler_ram_v | file:filename, file:write_file | apps/hls_phi/src/phi_partition_ram.erl | erlang, file, filename, hls_frame_layout, hls_partition_links, hls_partition_tile, hls_scheduler_plan, io_lib, json, lists, xls_scheduler_debug, xls_scheduler_observation, xls_scheduler_ram_v |
| apps/hls_phi/src/phi_phenom_topology.erl | phi_phenom_topology | hls_phi | topology/0 | — | include "../include/phi_protocol.hrl" | hls_topology | — | apps/hls_phi/src/phi_phenom_topology.erl | erlang |
| apps/hls_phi/src/phi_phenom_topology_dslx.erl | phi_phenom_topology_dslx | hls_phi | profile/0 to_dslx/0 | — | — | xls_topology_dslx | — | apps/hls_phi/src/phi_phenom_topology_dslx.erl | erlang, xls_topology_dslx |
| apps/hls_phi/src/phi_protocol_cli.erl | phi_protocol_cli | hls_phi | main/0, run/1 | — | — | hls_build, hls_cli, io, maps, phi_protocol_config | — | apps/hls_phi/src/phi_protocol_cli.erl | erlang, hls_build, hls_cli, io, maps, phi_protocol_config |
| apps/hls_phi/src/phi_protocol_config.erl | phi_protocol_config | hls_phi | repetition/2 | phi_protocol_cli | — | code, filename, hls_protocol_model, hls_source_build, lists, maps | — | apps/hls_phi/src/phi_protocol_config.erl | code, erlang, filename, lists, maps |
| apps/hls_phi/src/phi_protocol_model.erl | phi_protocol_model | hls_phi | derive/2, summary/1 | — | behaviour hls_protocol_model | hls_protocol_inventory, hls_protocol_model, lists, maps, only | — | apps/hls_phi/src/phi_protocol_model.erl | erlang, lists, maps |
| apps/hls_phi/src/phi_protocol_repetition.erl | phi_protocol_repetition | hls_phi | run/5, run/6 | — | — | erlang, lists, maps, phi_repetition_topology | — | apps/hls_phi/src/phi_protocol_repetition.erl | erlang, lists, maps, phi_repetition_topology |
| apps/hls_phi/src/phi_repetition_memory.erl | phi_repetition_memory | hls_phi | new/1, event/3, peer/2, progress/1, peer_role/1 correction_update/2 encode_peer/1, decode_peer/1 | phi_repetition_topology | include "../include/phi_protocol.hrl" | hls_nums, hls_pauli, lists, maps, order | — | apps/hls_phi/src/phi_repetition_memory.erl | erlang, hls_pauli, lists, maps |
| apps/hls_phi/src/phi_repetition_topology.erl | phi_repetition_topology | hls_phi | topology/1, topology/2, correction_update/2 profile/1 | phi_protocol_repetition, phi_shared_repetition_profile | include "../include/phi_protocol.hrl" | hls_nums, hls_pauli, hls_topology, lists, maps, phi_repetition_memory, xls_topology_dslx | — | apps/hls_phi/src/phi_repetition_topology.erl | erlang, lists, maps, phi_repetition_memory |
| apps/hls_phi/src/phi_shared_noise_topology_dslx.erl | phi_shared_noise_topology_dslx | hls_phi | profile/0, profile/1, scheduler_groups/0, scheduler_groups/1, scheduler_plan/0, scheduler_plan/1 to_dslx/0, to_dslx/1, to_dslx/2, to_dslx/3 | phi_memory_debug_top_v, phi_memory_gateway_dslx | — | hls_nums, hls_scheduler_plan, hls_topology, lists, maps, phi_noise_topology, xls_fabric_topology_dslx | — | apps/hls_phi/src/phi_shared_noise_topology_dslx.erl | erlang, hls_scheduler_plan, hls_topology, lists, maps, phi_noise_topology, xls_fabric_topology_dslx |
| apps/hls_phi/src/phi_shared_repetition_profile.erl | phi_shared_repetition_profile | hls_phi | profile/1 | — | — | maps, phi_repetition_topology | — | apps/hls_phi/src/phi_shared_repetition_profile.erl | erlang, maps, phi_repetition_topology |
| apps/hls_phi/src/phi_syndrome_replay_cell.erl | phi_syndrome_replay_cell | hls_phi | start_link/0, start_link/1, connect/2, stop/1, configure/5, offer_request/2 configuring/3, waiting/3, announcing/3, init/1 | — | behavior hls_statem, compile {parse_transform, hls_pack}, include "../include/phi_protocol.hrl" | hls_nums, hls_prng, hls_statem, hls_type | — | apps/hls_phi/src/phi_syndrome_replay_cell.erl | erlang, hls_gs, hls_nums, hls_pauli, hls_prng, hls_statem, hls_type, phi_field |
| apps/hls_phi/src/phi_torus_topology.erl | phi_torus_topology | hls_phi | topology/0, topology/2 | — | include "../include/phi_protocol.hrl" | hls_nums, hls_topology, lists | — | apps/hls_phi/src/phi_torus_topology.erl | erlang, lists |
| apps/hls_phi/src/phi_torus_topology_dslx.erl | phi_torus_topology_dslx | hls_phi | profile/0 to_dslx/0 | — | — | xls_topology_dslx | — | apps/hls_phi/src/phi_torus_topology_dslx.erl | erlang, xls_topology_dslx |
| apps/hls_snowflake/src/snowflake_actor_run.erl | snowflake_actor_run | hls_snowflake | run/3, run/4, write_vectors/4 | — | include "snowflake_actor_protocol.hrl" | erlang, file, hls_codec, hls_debug, hls_statem, hls_topology, io_lib, json, lists, maps, snowflake_actor_topology, snowflake_geometry, snowflake_vertex, snowflake_window, timer | file:filename, file:write_file | apps/hls_snowflake/src/snowflake_actor_run.erl | erlang, file, hls_codec, hls_debug, hls_statem, hls_topology, io_lib, json, lists, maps, snowflake_actor_topology, snowflake_vertex, snowflake_window, timer |
| apps/hls_snowflake/src/snowflake_actor_topology.erl | snowflake_actor_topology | hls_snowflake | topology/0, topology/2, topology/3, profile/3, geometry/2, vertex_config/2, ownership/1, write/3, write/4 | snowflake_actor_run, snowflake_source | include "snowflake_actor_protocol.hrl" | code, file, filelib, filename, hls_scheduler_plan, hls_topology, json, lists, maps, proplists, snowflake_coordinator, snowflake_geometry, xls_emitted, xls_scheduler_debug, xls_scheduler_ram_v | file:copy, file:filename, file:write_file | apps/hls_snowflake/src/snowflake_actor_topology.erl | code, erlang, file, filelib, filename, hls_scheduler_plan, hls_topology, json, lists, maps, proplists, snowflake_coordinator, snowflake_geometry, xls_emitted, xls_scheduler_debug, xls_scheduler_ram_v |
| apps/hls_snowflake/src/snowflake_barrier.erl | snowflake_barrier | hls_snowflake | init/1, configuring/3, starting/3, collecting/3, publishing/3, commanded/3 reduce/3 | — | behaviour hls_statem, compile {parse_transform, hls_pack}, include "snowflake_actor_protocol.hrl", include "snowflake_barrier.hrl" | hls_nums, hls_serial, hls_statem, hls_type | — | apps/hls_snowflake/src/snowflake_barrier.erl | erlang, hls_bool, hls_gs, hls_nums, hls_type |
| apps/hls_snowflake/src/snowflake_coordinator.erl | snowflake_coordinator | hls_snowflake | init/1, configuring/3, ready/3, executing/3, bounds/0 reduce/3 | snowflake_actor_topology | behavior hls_statem, compile {parse_transform, hls_pack}, include "snowflake_actor_protocol.hrl" | hls_bool, hls_nums, hls_serial, hls_statem, hls_type | — | apps/hls_snowflake/src/snowflake_coordinator.erl | erlang, hls_bool, hls_gs, hls_nums, hls_serial, hls_type |
| apps/hls_snowflake/src/snowflake_geometry.erl | snowflake_geometry | hls_snowflake | new/3 | snowflake_actor_run, snowflake_actor_topology, snowflake_window | — | lists, maps | — | apps/hls_snowflake/src/snowflake_geometry.erl | erlang, lists, maps |
| apps/hls_snowflake/src/snowflake_node.erl | snowflake_node | hls_snowflake | reset/1, drop/4, grow/3, merge/9, merge_surface/11 | snowflake_window | compile {parse_transform, hls_pack}, include "snowflake_node.hrl", include "snowflake_node_impl.hrl" | — | — | apps/hls_snowflake/src/snowflake_node.erl | erlang, hls_bool, hls_gs, hls_nums, hls_type |
| apps/hls_snowflake/src/snowflake_source.erl | snowflake_source | hls_snowflake | config/0, topology/0 | — | — | code, configuration, filename, hls_source_config, hls_topology, snowflake_actor_topology | — | apps/hls_snowflake/src/snowflake_source.erl | code, erlang, filename, snowflake_actor_topology |
| apps/hls_snowflake/src/snowflake_vertex.erl | snowflake_vertex | hls_snowflake | init/1, geometry/3, configuring/3, configured/3, ready/3, shifting/3, snapshotting/3, transferring/3, snapshot/1, reduce/3 | snowflake_actor_run | behaviour hls_statem, compile {parse_transform, hls_pack}, include "snowflake_actor_protocol.hrl", include "snowflake_node_impl.hrl" | hls_bool, hls_lists, hls_nums, hls_serial, hls_statem, hls_type | — | apps/hls_snowflake/src/snowflake_vertex.erl | erlang, hls_bool, hls_gs, hls_lists, hls_nums, hls_serial, hls_type |
| apps/hls_snowflake/src/snowflake_window.erl | snowflake_window | hls_snowflake | new/3, decode/2, snapshot/1, stream/4, profile/4 | snowflake_actor_run | include "snowflake_node.hrl" | lists, maps, snowflake_geometry, snowflake_node | — | apps/hls_snowflake/src/snowflake_window.erl | erlang, lists, maps, snowflake_geometry, snowflake_node |
| apps/hls_spacetime_protocol/src/xls_protocol_spacetime.erl | xls_protocol_spacetime | hls_spacetime_protocol | plan/4, tsv/1, observation_digest/1 | xls_protocol_spacetime_capture | — | binary, crypto, file, filename, io_lib, json, lists, maps, re | file:filename, file:read_file | apps/hls_spacetime_protocol/src/xls_protocol_spacetime.erl | binary, crypto, erlang, file, filename, io_lib, json, lists, maps, re |
| apps/hls_spacetime_protocol/src/xls_protocol_spacetime_capture.erl | xls_protocol_spacetime_capture | hls_spacetime_protocol | bundle/3 | — | — | hls_spacetime, hls_spacetime_trace, io_lib, lists, maps, xls_protocol_spacetime | — | apps/hls_spacetime_protocol/src/xls_protocol_spacetime_capture.erl | erlang, hls_spacetime, hls_spacetime_trace, io_lib, lists, maps, xls_protocol_spacetime |
| src/app/hls_fabric_app.erl | hls_fabric_app | hls_fabric | start/2, stop/1 | — | behaviour application | application, hls_fabric_sup | — | apps/hls_fabric/src/app/hls_fabric_app.erl | erlang, hls_fabric_sup |
| src/app/hls_fabric_sup.erl | hls_fabric_sup | hls_fabric | start_link/0 start_node/4, stop_node/1 init/1 | hls_fabric_app | behaviour supervisor | hls_node, supervisor | — | apps/hls_fabric/src/app/hls_fabric_sup.erl | erlang, supervisor |
| src/runtime/hls_dma_device.erl | hls_dma_device | hls_fabric | await/3, endpoint_state/2, status/3, idle/1, healthy/1, status_line/2 await_broker/2, close_broker/2 | — | — | binary, erlang, file, filelib, filename, hls_fabric, lists, os, timer | file:filename, file:read_file, file:read_file_info, file:write_file, os:cmd | apps/hls_fabric/src/runtime/hls_dma_device.erl | binary, erlang, file, filelib, filename, hls_fabric, lists, os, timer |
| src/runtime/hls_partition_stream.erl | hls_partition_stream | hls_fabric | start_link/3, submit/2, next/2, info/1, stop/1 init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2 | — | behaviour gen_server | erlang, gen_server, hardware, hls_fabric, hls_partition_wire, lists, maps, queue | — | apps/hls_fabric/src/runtime/hls_partition_stream.erl | erlang, gen_server, hls_fabric, hls_partition_wire, lists, maps, queue |
| src/runtime/hls_protocol_mixed_admission.erl | hls_protocol_mixed_admission | hls_fabric | new/2, deliver/3 down/3, retire/1 info/1 | hls_protocol_mixed_stream | — | erlang, hls_statem, lists, maps | — | apps/hls_fabric/src/runtime/hls_protocol_mixed_admission.erl | erlang, hls_statem, lists, maps |
| src/runtime/hls_protocol_mixed_host.erl | hls_protocol_mixed_host | hls_fabric | service/3, connect/3, startup/1 controls/2, external/4, native_event/3 | hls_protocol_mixed_stream | — | hls_codec, hls_node, hls_partition_wire, hls_protocol_application_codec, hls_record_codec, lists, maps | — | apps/hls_fabric/src/runtime/hls_protocol_mixed_host.erl | erlang, hls_codec, hls_partition_wire, hls_protocol_application_codec, hls_record_codec, lists, maps |
| src/runtime/hls_protocol_mixed_queue.erl | hls_protocol_mixed_queue | hls_fabric | new/4, offer/4 next/1, credit/5, delivery/6 invalidate/1, info/1 | hls_protocol_mixed_stream | — | hls_protocol_mixed_codec, hls_protocol_mixed_schema, lists, maps, queue, view | — | apps/hls_fabric/src/runtime/hls_protocol_mixed_queue.erl | erlang, hls_protocol_mixed_codec, lists, maps, queue |
| src/runtime/hls_protocol_mixed_stream.erl | hls_protocol_mixed_stream | hls_fabric | start_link/5, submit/2, next/2, info/1, stop/1 init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2 | — | behaviour gen_server | erlang, gen_server, hls_fabric, hls_partition_wire, hls_protocol_bridge_wire, hls_protocol_mixed_admission, hls_protocol_mixed_codec, hls_protocol_mixed_host, hls_protocol_mixed_queue, hls_statem, lists, maps, queue | — | apps/hls_fabric/src/runtime/hls_protocol_mixed_stream.erl | erlang, gen_server, hls_fabric, hls_protocol_bridge_wire, hls_protocol_mixed_admission, hls_protocol_mixed_codec, hls_protocol_mixed_host, hls_protocol_mixed_queue, hls_statem, lists, maps, queue |
| src/runtime/hls_protocol_relay_queue.erl | hls_protocol_relay_queue | hls_fabric | new/2, event/3 next/1, complete/2 invalidate/1, info/1 | hls_protocol_stream | — | hls_protocol_codec, hls_protocol_routing, lists, maps | — | apps/hls_fabric/src/runtime/hls_protocol_relay_queue.erl | erlang, hls_protocol_codec, hls_protocol_routing, lists, maps |
| src/runtime/hls_protocol_routing.erl | hls_protocol_routing | hls_fabric | plan/1, roles/1, routes/1 | hls_protocol_deployment, hls_protocol_relay_queue, hls_protocol_stream | — | lists, maps | — | apps/hls_fabric/src/runtime/hls_protocol_routing.erl | erlang, lists, maps |
| src/runtime/hls_protocol_stream.erl | hls_protocol_stream | hls_fabric | start_link/3, start_application/3, submit/2, next/2, info/1, stop/1 init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2 | — | behaviour gen_server | erlang, gen_server, hls_fabric, hls_partition_wire, hls_protocol_application_codec, hls_protocol_bridge_wire, hls_protocol_relay_queue, hls_protocol_routing, lists, maps, queue | — | apps/hls_fabric/src/runtime/hls_protocol_stream.erl | erlang, gen_server, hls_fabric, hls_partition_wire, hls_protocol_application_codec, hls_protocol_bridge_wire, hls_protocol_relay_queue, hls_protocol_routing, lists, maps, queue |
| src/runtime/inspection/hls_link_diagnostics.erl | hls_link_diagnostics | hls_fabric | packet_boundary/3, packet_counters/1, packet_delta/2 packet_adapter_flags/1, packet_mac_flags/1, packet_trace_event/1, packet_trace_flags/1 private_boundary/2, private_counters/1, private_delta/2 stage_boundary/1, stage_counters/1, stage_delta/2, stage_flags/1, stage_trace_flags/1 counter_delta/2 | — | — | lists, maps | — | apps/hls_fabric/src/runtime/inspection/hls_link_diagnostics.erl | erlang, lists, maps |
| src/runtime/inspection/hls_process_profile.erl | hls_process_profile | hls_fabric | capture/3 write/2 | — | — | erlang, file, hls_debug, hls_debug_catalog, io_lib, json, lists, maps, timer, unicode | file:filename, file:write_file | apps/hls_fabric/src/runtime/inspection/hls_process_profile.erl | erlang, file, hls_debug, hls_debug_catalog, io_lib, json, lists, maps, timer, unicode |
| src/runtime/inspection/hls_protocol_observation.erl | hls_protocol_observation | hls_fabric | open/2, catalog/2 | — | — | binary, crypto, hls_actor_identity, hls_debug, hls_topology_debug, lists, maps | — | apps/hls_fabric/src/runtime/inspection/hls_protocol_observation.erl | binary, crypto, erlang, hls_actor_identity, hls_debug, hls_topology_debug, lists, maps |
| src/runtime/inspection/hls_shared_observation.erl | hls_shared_observation | hls_fabric | open/2, open/3, bind/2 decode_observation/2, mailbox_observation/2, actor_fields/1 | hls_node_topology, hls_partition_tile_debug, hls_shared_debug_catalog | — | hls_debug_catalog, hls_topology_debug, maps | — | apps/hls_fabric/src/runtime/inspection/hls_shared_observation.erl | erlang, hls_debug_catalog, hls_topology_debug, maps |
| src/runtime/node/hls_local_dist.erl | hls_local_dist | hls_fabric | listen/1, listen/2, accept/1, accept_connection/5, setup/5, close/1, select/1, address/0, is_node_name/1, setopts/2, getopts/2 local_setup/6 | — | include_lib "kernel/include/dist.hrl", include_lib "kernel/include/dist_util.hrl", include_lib "kernel/include/net_address.hrl" | dist_util, gen_server, gen_tcp, hls_node, inet_tcp_dist, string | — | apps/hls_fabric/src/runtime/node/hls_local_dist.erl | dist_util, erlang, gen_server, hls_node, inet_tcp_dist, string |
| src/runtime/node/hls_node.erl | hls_node | hls_fabric | start_link/4, stop/1, info/1, services/1 start_manager/5, local_manager/1 init/1, handle_call/3, handle_cast/2, handle_info/2 | hls_fabric_sup, hls_local_dist, hls_node_connection, hls_node_sup, hls_protocol_mixed_host | behaviour gen_server | binary, error, gen_server, gen_tcp, hls_fabric, hls_node_binding, hls_node_connections, hls_node_sup, hls_node_wire, hls_service_schema, inet, lists, maps, string, supervisor | — | apps/hls_fabric/src/runtime/node/hls_node.erl | binary, erlang, gen_server, gen_tcp, hls_fabric, hls_node_binding, hls_node_connections, hls_node_sup, hls_node_wire, hls_service_schema, inet, lists, maps, string |
| src/runtime/node/hls_node_acceptor.erl | hls_node_acceptor | hls_fabric | start_link/1 init/1 | — | — | gen_server, gen_tcp, hls_node_connections, hls_node_sup, proc_lib | — | apps/hls_fabric/src/runtime/node/hls_node_acceptor.erl | erlang, gen_server, gen_tcp, hls_node_connections, hls_node_sup, proc_lib |
| src/runtime/node/hls_node_connection.erl | hls_node_connection | hls_fabric | start_link/2 init/1, handle_call/3, handle_cast/2, handle_info/2, format_status/1 | hls_node_connections | behaviour gen_server | erlang, gen_server, gen_tcp, hls_debug, hls_fabric, hls_gs, hls_node, hls_node_binding, hls_node_wire, inet, lists, maps, queue | — | apps/hls_fabric/src/runtime/node/hls_node_connection.erl | erlang, gen_server, gen_tcp, hls_debug, hls_fabric, hls_gs, hls_node_binding, hls_node_wire, inet, lists, maps, queue |
| src/runtime/node/hls_node_connections.erl | hls_node_connections | hls_fabric | start_link/0, start/3 init/1 | hls_node, hls_node_acceptor | behaviour supervisor | hls_node_connection, supervisor | — | apps/hls_fabric/src/runtime/node/hls_node_connections.erl | erlang, supervisor |
| src/runtime/node/hls_node_sup.erl | hls_node_sup | hls_fabric | start_link/4, child/2 init/1 | hls_node, hls_node_acceptor | behaviour supervisor | hls_node, lists, supervisor | — | apps/hls_fabric/src/runtime/node/hls_node_sup.erl | erlang, lists, supervisor |
| src/runtime/node/hls_node_wire.erl | hls_node_wire | hls_fabric | register/3, handshake/3, handshake_start/2, handshake_step/2 pid/3 decode/1, encode/1, encode/2, reply/3 | hls_node, hls_node_connection | include_lib "kernel/include/dist.hrl" | binary, crypto, erlang, gen_tcp, inet, maps | — | apps/hls_fabric/src/runtime/node/hls_node_wire.erl | binary, crypto, erlang, gen_tcp, inet, maps |
| src/wire/hls_host_codec.erl | hls_host_codec | hls_fabric | check/1 | hls_host_codec_plan, hls_node_binding, hls_partition_wire, hls_protocol_application_schema, hls_protocol_mixed, hls_protocol_mixed_codec, hls_protocol_mixed_schema | — | hls_record_codec, maps | — | apps/hls_fabric/src/wire/hls_host_codec.erl | erlang, hls_record_codec, maps |
| src/wire/hls_node_binding.erl | hls_node_binding | hls_fabric | validate/1, encode_cast/2 | hls_node, hls_node_connection | — | hls_codec, hls_host_codec, hls_record_codec, lists, maps | — | apps/hls_fabric/src/wire/hls_node_binding.erl | erlang, hls_codec, hls_host_codec, hls_record_codec, lists, maps |
| src/wire/hls_partition_ingress.erl | hls_partition_ingress | hls_fabric | commands/5, select/5 | hls_partition_wire, hls_protocol_application_codec | — | hls_codec, hls_frame_layout, hls_record_codec, lists, maps | — | apps/hls_fabric/src/wire/hls_partition_ingress.erl | erlang, hls_codec, hls_frame_layout, hls_record_codec, lists |
| src/wire/hls_partition_wire.erl | hls_partition_wire | hls_fabric | check/1 command/2, control_payload/1, event/4 | hls_partition_stream, hls_protocol_application_codec, hls_protocol_mixed_codec, hls_protocol_mixed_host, hls_protocol_mixed_stream, hls_protocol_stream | — | binary, hls_codec, hls_fabric, hls_host_codec, hls_partition_ingress, hls_protocol_envelope, hls_record_codec, lists, maps | — | apps/hls_fabric/src/wire/hls_partition_wire.erl | binary, erlang, hls_codec, hls_host_codec, hls_partition_ingress, hls_protocol_envelope, hls_record_codec, lists, maps |
| src/wire/hls_protocol_application_codec.erl | hls_protocol_application_codec | hls_fabric | control/2, delivery/2 event/4 | hls_protocol_mixed_host, hls_protocol_stream | — | hls_frame_layout, hls_partition_ingress, hls_partition_wire, hls_protocol_application_schema, maps | — | apps/hls_fabric/src/wire/hls_protocol_application_codec.erl | erlang, hls_frame_layout, hls_partition_ingress, hls_partition_wire, maps |
| src/wire/hls_protocol_application_schema.erl | hls_protocol_application_schema | hls_fabric | — | hls_protocol_application, hls_protocol_application_binding, hls_protocol_application_codec, hls_protocol_deployment, hls_protocol_mixed, hls_protocol_mixed_schema | — | hls_frame_layout, hls_host_codec | — | apps/hls_fabric/src/wire/hls_protocol_application_schema.erl | erlang |
| src/wire/hls_protocol_bridge_wire.erl | hls_protocol_bridge_wire | hls_fabric | attach/2, command/2 packet/1, event/3 | hls_protocol_mixed_stream, hls_protocol_stream | — | hls_fabric, hls_protocol_envelope | — | apps/hls_fabric/src/wire/hls_protocol_bridge_wire.erl | erlang, hls_protocol_envelope |
| src/wire/hls_protocol_codec.erl | hls_protocol_codec | hls_fabric | encode/2, decode/2 | hls_protocol_codec_plan, hls_protocol_inbox, hls_protocol_mixed_codec, hls_protocol_mixed_schema, hls_protocol_partition, hls_protocol_relay_queue, xls_protocol_codec, xls_protocol_network | — | hls_frame_layout, lists | — | apps/hls_fabric/src/wire/hls_protocol_codec.erl | erlang, hls_frame_layout, lists |
| src/wire/hls_protocol_envelope.erl | hls_protocol_envelope | hls_fabric | fields/1 pack_packet/1, unpack_packet/1, pack_rectangle/2 | hls_partition_wire, hls_protocol_bridge_wire, xls_protocol_envelope | — | binary, hls_nums, hls_record, hls_type, lists, maps | — | apps/hls_fabric/src/wire/hls_protocol_envelope.erl | binary, erlang, hls_nums, hls_record, hls_type, lists, maps |
| src/wire/hls_protocol_mixed_codec.erl | hls_protocol_mixed_codec | hls_fabric | check/1 encode/2, encode/3, decode/3 | hls_protocol_mixed_queue, hls_protocol_mixed_stream | — | hls_frame_layout, hls_host_codec, hls_partition_wire, hls_protocol_codec, hls_protocol_mixed_schema, hls_record_codec, lists, maps | — | apps/hls_fabric/src/wire/hls_protocol_mixed_codec.erl | erlang, hls_frame_layout, hls_host_codec, hls_partition_wire, hls_protocol_codec, hls_record_codec, lists, maps |
| src/wire/hls_protocol_mixed_schema.erl | hls_protocol_mixed_schema | hls_fabric | — | hls_protocol_mixed, hls_protocol_mixed_codec, hls_protocol_mixed_queue | — | hls_host_codec, hls_protocol_application_schema, hls_protocol_codec, hls_record_codec | — | apps/hls_fabric/src/wire/hls_protocol_mixed_schema.erl | erlang |

## hls_spacetime modules

| Source / responsibility | Module | Current and Stage 1 app | Explicit exports | Candidate consumers | Compile declarations | Remote references | Resource or dispatch calls | Stage 1 path | BEAM imports |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| src/hls_spacetime.erl | hls_spacetime | hls_spacetime | validate/1, encode/1 | hls_spacetime_artifact, hls_spacetime_cli, hls_spacetime_import, hls_spacetime_storage, xls_protocol_spacetime_capture | — | digraph, digraph_utils, erlang, error, hls_spacetime_physical, hls_spacetime_storage, json, lists, maps, unicode | — | apps/hls_spacetime/src/hls_spacetime.erl | digraph, digraph_utils, erlang, hls_spacetime_physical, hls_spacetime_storage, json, lists, maps, unicode |
| src/hls_spacetime_artifact.erl | hls_spacetime_artifact | hls_spacetime | read/1, write_bundle/2, write_catalogue/2 | hls_spacetime_cli | include_lib "kernel/include/file.hrl" | binary, code, crypto, file, filename, hls_spacetime, hls_spacetime_import, hls_spacetime_physical, json, lists, maps | code:ensure_loaded, file:filename, file:filename_all, file:make_dir, file:read_file, file:read_file_info, file:write_file | apps/hls_spacetime/src/hls_spacetime_artifact.erl | binary, code, crypto, erlang, file, filename, hls_spacetime, hls_spacetime_physical, json, lists, maps |
| src/hls_spacetime_cli.erl | hls_spacetime_cli | hls_spacetime | main/1, run/1 | — | — | binary, crypto, file, hls_spacetime, hls_spacetime_artifact, hls_spacetime_import, hls_spacetime_physical, hls_spacetime_sdf, hls_spacetime_sdf_arcs, io, json, maps, unicode | file:consult, file:filename, file:write_file | apps/hls_spacetime/src/hls_spacetime_cli.erl | binary, crypto, erlang, file, hls_spacetime, hls_spacetime_artifact, hls_spacetime_import, hls_spacetime_sdf, hls_spacetime_sdf_arcs, io, json, unicode |
| src/hls_spacetime_import.erl | hls_spacetime_import | hls_spacetime | read/3, attach/3 | hls_spacetime_artifact, hls_spacetime_cli | include_lib "kernel/include/file.hrl" | binary, error, file, filename, hls_spacetime, hls_spacetime_physical, hls_spacetime_sdf, json, lists, maps, re, unicode | file:close, file:filename_all, file:io_device, file:open, file:read_file, file:read_file_info, file:read_line | apps/hls_spacetime/src/hls_spacetime_import.erl | binary, erlang, file, filename, hls_spacetime, hls_spacetime_physical, hls_spacetime_sdf, json, lists, maps, re, unicode |
| src/hls_spacetime_native.erl | hls_spacetime_native | hls_spacetime | validate/3 | hls_spacetime_physical | — | context, hls_spacetime_sdf, lists, maps, unicode | — | apps/hls_spacetime/src/hls_spacetime_native.erl | erlang, hls_spacetime_sdf, lists, maps, unicode |
| src/hls_spacetime_physical.erl | hls_spacetime_physical | hls_spacetime | validate/3 | hls_spacetime, hls_spacetime_artifact, hls_spacetime_cli, hls_spacetime_import | — | hls_spacetime_native, lists, maps, unicode | — | apps/hls_spacetime/src/hls_spacetime_physical.erl | erlang, hls_spacetime_native, lists, maps, unicode |
| src/hls_spacetime_sdf.erl | hls_spacetime_sdf | hls_spacetime | read/2, validate/1, describe/1, validate_description/1 | hls_spacetime_cli, hls_spacetime_import, hls_spacetime_native, hls_spacetime_sdf_arcs | include_lib "kernel/include/file.hrl" | binary, crypto, file, json, lists, maps, re, unicode | file:filename_all, file:read_file, file:read_file_info | apps/hls_spacetime/src/hls_spacetime_sdf.erl | binary, crypto, erlang, file, json, lists, re, unicode |
| src/hls_spacetime_sdf_arcs.erl | hls_spacetime_sdf_arcs | hls_spacetime | project/1 | hls_spacetime_cli | — | binary, error, hls_spacetime_sdf, lists, maps, re | — | apps/hls_spacetime/src/hls_spacetime_sdf_arcs.erl | binary, erlang, lists, re |
| src/hls_spacetime_storage.erl | hls_spacetime_storage | hls_spacetime | validate/3 | hls_spacetime | — | hls_spacetime, lists, maps | — | apps/hls_spacetime/src/hls_spacetime_storage.erl | erlang, lists, maps |
| src/hls_spacetime_trace.erl | hls_spacetime_trace | hls_spacetime | read/1, fold/3 | xls_protocol_spacetime_capture | include_lib "kernel/include/file.hrl" | binary, file, lists, maps | file:close, file:filename_all, file:io_device, file:open, file:read_file_info, file:read_line | apps/hls_spacetime/src/hls_spacetime_trace.erl | binary, erlang, file, lists, maps |

## Supporting files

Assets, fixtures, headers, scripts and configuration grouped by their current application or repository directory.

### erl_hls / erl_hls

- `.github/actions/diagnostics/action.yml`
- `.github/workflows/ci.yml`
- `.github/workflows/source-quality.yml`
- `.gitignore`
- `attic/hls_debug_monitor.v`
- `bin/hlsc`
- `include/erl_parse.hrl`
- `priv/rtl/debug/hls_actor_snapshot.v`
- `priv/rtl/debug/hls_debug_frame_rx.v`
- `priv/rtl/debug/hls_debug_monitor.v`
- `priv/rtl/debug/hls_debug_route.v`
- `priv/rtl/debug/hls_debug_tap.v`
- `priv/rtl/debug/hls_topology_debug.v`
- `priv/rtl/debug/hls_trace_store.v`
- `priv/rtl/fabric/hls_fabric_egress.v`
- `priv/rtl/fabric/hls_fabric_ingress.v`
- `priv/rtl/hls_1r1w_ram.v`
- `priv/rtl/hls_1rw_ram.v`
- `priv/tools/compile_source_build.py`
- `priv/tools/compile_xls.py`
- `priv/xls/debug/hls_debug_framing.x`
- `priv/xls/debug/hls_debug_observer.x`
- `priv/xls/debug/hls_debug_server.x`
- `priv/xls/debug/hls_debug_trace.x`
- `priv/xls/debug/hls_debug_types.x`
- `priv/xls/fabric/hls_fabric_router.x`
- `priv/xls/fabric/hls_spatial_router.x`
- `priv/xls/lib/arbitration.x`
- `priv/xls/lib/axis.x`
- `priv/xls/lib/bram.x`
- `priv/xls/lib/direct_mailbox_observation.x`
- `priv/xls/lib/frame_config.x`
- `priv/xls/lib/frame_transport.x`
- `priv/xls/lib/hls_bits.x`
- `priv/xls/lib/hls_failure.x`
- `priv/xls/lib/hls_fixed.x`
- `priv/xls/lib/hls_float.x`
- `priv/xls/lib/hls_integer.x`
- `priv/xls/lib/hls_lists.x`
- `priv/xls/lib/hls_multiply.x`
- `priv/xls/lib/hls_patterns.x`
- `priv/xls/lib/hls_reply.x`
- `priv/xls/lib/hls_serial.x`
- `priv/xls/lib/hls_server.x`
- `priv/xls/lib/hls_vec.x`
- `rebar.config`
- `rebar.lock`
- `source-contracts.json`
- `src/backend/xls/expressions/xls_clause_lower.hrl`
- `src/erl_hls.app.src`
- `src/examples/regsvc/regsvc.erl.x`
- `src/examples/regsvc/regsvc_core_adapter.v`
- `src/examples/regsvc/regsvc_debug_top.v`
- `src/examples/telemetry/telemetry.hrl`
- `test/fabric_peer.py`
- `test/hls_actor_constants_tests.erl`
- `test/hls_actor_debug_fixture.erl`
- `test/hls_actor_debug_helpers.hrl`
- `test/hls_actor_interface_tests.erl`
- `test/hls_actor_observation_fixture.erl`
- `test/hls_actor_source_tests.erl`
- `test/hls_companion_provider.erl`
- `test/hls_compiler_bootstrap_tests.erl`
- `test/hls_data_cell_fixture.erl`
- `test/hls_debug_catalog_tests.erl`
- `test/hls_debug_target_tests.erl`
- `test/hls_debug_trace_live.erl`
- `test/hls_deferred_fixture.erl`
- `test/hls_deferred_tests.erl`
- `test/hls_dense_statem_fixture.erl`
- `test/hls_dense_topology_dslx.erl`
- `test/hls_diagnostic_tests.erl`
- `test/hls_direct_actor_debug_tests.erl`
- `test/hls_direct_debug_fixture.erl`
- `test/hls_fabric_backpressure_tests.erl`
- `test/hls_fabric_client_tests.erl`
- `test/hls_fabric_services_live.erl`
- `test/hls_fabric_test_wire.erl`
- `test/hls_fabric_tests.erl`
- `test/hls_fixed_tests.erl`
- `test/hls_float_arithmetic_tests.erl`
- `test/hls_float_dslx.erl`
- `test/hls_float_fixture.erl`
- `test/hls_float_lowering_tests.erl`
- `test/hls_float_tests.erl`
- `test/hls_frame_codec_tests.erl`
- `test/hls_frame_layout_tests.erl`
- `test/hls_gather_debug_tests.erl`
- `test/hls_grid_cell_fixture.erl`
- `test/hls_grid_topology_fixture.erl`
- `test/hls_indexed_gather_tests.erl`
- `test/hls_interface_scaling_tests.erl`
- `test/hls_large_mailbox_fixture.erl`
- `test/hls_lists_tests.erl`
- `test/hls_logical_dslx.erl`
- `test/hls_logical_fixture.erl`
- `test/hls_logical_tests.erl`
- `test/hls_mailbox_debug_fixture.erl`
- `test/hls_mailbox_tests.erl`
- `test/hls_mixed_collector.erl`
- `test/hls_mixed_cpu_tests.erl`
- `test/hls_mixed_protocol.hrl`
- `test/hls_mixed_source.erl`
- `test/hls_mixed_topology_dslx.erl`
- `test/hls_mixed_topology_tests.erl`
- `test/hls_mixed_worker.erl`
- `test/hls_nested_records_dslx.erl`
- `test/hls_nested_records_fixture.erl`
- `test/hls_nested_records_tests.erl`
- `test/hls_numeric_dslx.erl`
- `test/hls_numeric_lowering_tests.erl`
- `test/hls_nums_tests.erl`
- `test/hls_parametric_topology_tests.erl`
- `test/hls_prng_tests.erl`
- `test/hls_query_cell_fixture.erl`
- `test/hls_record_codec_tests.erl`
- `test/hls_record_defaults_tests.erl`
- `test/hls_reduction_debug_tests.erl`
- `test/hls_reduction_failure_fixture.erl`
- `test/hls_reduction_mask_tests.erl`
- `test/hls_reduction_tests.erl`
- `test/hls_reply_fixture.erl`
- `test/hls_retained_calls_tests.erl`
- `test/hls_routing_fixture.hrl`
- `test/hls_routing_topology_fixture.erl`
- `test/hls_runtime_package_tests.erl`
- `test/hls_serial_dslx.erl`
- `test/hls_serial_fixture.erl`
- `test/hls_serial_lowering_tests.erl`
- `test/hls_serial_tests.erl`
- `test/hls_service_contract_tests.erl`
- `test/hls_source_dslx.erl`
- `test/hls_source_fixture.erl`
- `test/hls_source_tests.erl`
- `test/hls_state_serialization_tests.erl`
- `test/hls_statem_collection_fixture.erl`
- `test/hls_statem_dynamic_actions_fixture.erl`
- `test/hls_statem_event_fixture.erl`
- `test/hls_statem_event_tests.erl`
- `test/hls_statem_gather_fixture.erl`
- `test/hls_statem_gather_tests.erl`
- `test/hls_statem_reduction_fixture.erl`
- `test/hls_statem_reduction_reply_fixture.erl`
- `test/hls_statem_reduction_tests.erl`
- `test/hls_statem_reply_dslx.erl`
- `test/hls_statem_reply_fixture.erl`
- `test/hls_statem_tests.erl`
- `test/hls_toolchain_tests.erl`
- `test/hls_topology_debug_live.erl`
- `test/hls_topology_debug_tests.erl`
- `test/hls_topology_ingress_tests.erl`
- `test/hls_topology_layout_fixture.erl`
- `test/hls_topology_reordered_fixture.erl`
- `test/hls_topology_source_fixture.erl`
- `test/hls_topology_tests.erl`
- `test/hls_type_tests.erl`
- `test/hls_variable_width_pack_fixture.erl`
- `test/hls_vec_tests.erl`
- `test/ordered_egress_actor.erl`
- `test/ordered_egress_topology.erl`
- `test/packed_samples_live.erl`
- `test/regsvc_cpu_tests.erl`
- `test/rtl/application_frames_tb.sv`
- `test/rtl/application_service_tb.sv`
- `test/rtl/debug/hls_actor_observation_tb.sv`
- `test/rtl/debug/hls_actor_snapshot_formal.sv`
- `test/rtl/debug/hls_actor_snapshot_tb.sv`
- `test/rtl/debug/hls_debug_route_tb.sv`
- `test/rtl/debug/hls_debug_sampling_formal.sv`
- `test/rtl/debug/hls_debug_sampling_tb.sv`
- `test/rtl/debug/hls_debug_server_tb.sv`
- `test/rtl/debug/hls_debug_tap_tb.sv`
- `test/rtl/debug/hls_debug_trace_live_tb.sv`
- `test/rtl/debug/hls_topology_debug_tb.sv`
- `test/rtl/debug/hls_trace_store_tb.sv`
- `test/rtl/debug/memory_export_fixture.sv`
- `test/rtl/debug/memory_export_tb.sv`
- `test/rtl/deferred_server_tb.sv`
- `test/rtl/direct_admission_formal.sv`
- `test/rtl/direct_admission_tb.sv`
- `test/rtl/fabric_egress_formal.sv`
- `test/rtl/fabric_ingress_formal.sv`
- `test/rtl/fabric_router_tb.sv`
- `test/rtl/fabric_services_tb.sv`
- `test/rtl/hls_fabric_host_tx_tb.sv`
- `test/rtl/hls_float_actor_tb.sv`
- `test/rtl/hls_float_probe_tb.sv`
- `test/rtl/hls_serial_tb.sv`
- `test/rtl/logical_codecs_tb.sv`
- `test/rtl/logical_service_tb.sv`
- `test/rtl/logical_topology_tb.sv`
- `test/rtl/mixed_effect_windows_tb.sv`
- `test/rtl/ordered_egress_topology_tb.sv`
- `test/rtl/packed_samples_tb.sv`
- `test/rtl/regsvc_bridge_tb.sv`
- `test/rtl/regsvc_fabric_fixture.sv`
- `test/rtl/regsvc_pair_harness.v`
- `test/rtl/regsvc_pair_harness_tb.sv`
- `test/rtl/regsvc_pair_tb.sv`
- `test/rtl/service_contracts_tb.sv`
- `test/rtl/statem_reply_direct_tb.sv`
- `test/rtl/statem_reply_topology_tb.sv`
- `test/rtl/telemetry_example_tb.sv`
- `test/rtl/xls_collection_tb.sv`
- `test/rtl/xls_comparison_tb.sv`
- `test/rtl/xls_control_failure_tb.sv`
- `test/rtl/xls_init_gs_tb.sv`
- `test/rtl/xls_init_topology.template.v`
- `test/rtl/xls_init_topology_tb.sv`
- `test/rtl/xls_integer_tb.sv`
- `test/rtl/xls_shift_tb.sv`
- `test/rtl/xls_sim_axis.h`
- `test/rtl/xls_sim_bridge.c`
- `test/rtl/xls_state_updates_tb.sv`
- `test/rtl/xls_static_integer_tb.sv`
- `test/telemetry_example_fixture.erl`
- `test/telemetry_example_tests.erl`
- `test/xls_actor_observation_tests.erl`
- `test/xls_actor_outbox_fixture.erl`
- `test/xls_actor_program_tests.erl`
- `test/xls_binary_dslx.erl`
- `test/xls_binary_fixture.erl`
- `test/xls_binary_tests.erl`
- `test/xls_callback_result_tests.erl`
- `test/xls_clause_expr_tests.erl`
- `test/xls_collection_dslx.erl`
- `test/xls_collection_tests.erl`
- `test/xls_comparison_dslx.erl`
- `test/xls_comparison_fixture.erl`
- `test/xls_comparison_tests.erl`
- `test/xls_compiler_boundary_tests.erl`
- `test/xls_control_failure_dslx.erl`
- `test/xls_control_failure_fixture.erl`
- `test/xls_control_failure_tests.erl`
- `test/xls_differential_worker.erl`
- `test/xls_dslx_imports_tests.erl`
- `test/xls_dslx_tests.erl`
- `test/xls_entry_branch_dslx.erl`
- `test/xls_entry_branch_fixture.erl`
- `test/xls_entry_ir_tests.erl`
- `test/xls_entry_outcome_dslx.erl`
- `test/xls_entry_outcome_fixture.erl`
- `test/xls_entry_reduction_fixture.erl`
- `test/xls_entry_storage_dslx.erl`
- `test/xls_entry_storage_fixture.erl`
- `test/xls_entry_storage_tests.erl`
- `test/xls_failure_provider_fixture.erl`
- `test/xls_failure_sites_tests.erl`
- `test/xls_hardware_source_closure_tests.erl`
- `test/xls_helpers_dslx.erl`
- `test/xls_helpers_fixture.erl`
- `test/xls_helpers_tests.erl`
- `test/xls_init_dslx.erl`
- `test/xls_init_gs_fixture.erl`
- `test/xls_init_statem_fixture.erl`
- `test/xls_init_tests.erl`
- `test/xls_integer_dslx.erl`
- `test/xls_known_bits_dslx.erl`
- `test/xls_known_bits_fixture.erl`
- `test/xls_known_bits_tests.erl`
- `test/xls_large_mailbox_dslx.erl`
- `test/xls_literal_fixture.erl`
- `test/xls_literal_types_dslx.erl`
- `test/xls_literal_types_tests.erl`
- `test/xls_message_bits_tests.erl`
- `test/xls_message_facts_tests.erl`
- `test/xls_name_hardening_tests.erl`
- `test/xls_named_bits_tests.erl`
- `test/xls_names_dslx.erl`
- `test/xls_names_fixture.erl`
- `test/xls_names_gs_fixture.erl`
- `test/xls_names_tests.erl`
- `test/xls_nums_tests.erl`
- `test/xls_parse_tests.erl`
- `test/xls_pattern_totality_tests.erl`
- `test/xls_patterns_dslx.erl`
- `test/xls_patterns_fixture.erl`
- `test/xls_patterns_tests.erl`
- `test/xls_phase_values_dslx.erl`
- `test/xls_phase_values_fixture.erl`
- `test/xls_phase_values_tests.erl`
- `test/xls_regression_fixtures.erl`
- `test/xls_shift_dslx.erl`
- `test/xls_shift_tests.erl`
- `test/xls_short_circuit_dslx.erl`
- `test/xls_short_circuit_fixture.erl`
- `test/xls_statem_entry_tests.erl`
- `test/xls_statem_gather_dslx.erl`
- `test/xls_statem_gather_tests.erl`
- `test/xls_statem_identity_tests.erl`
- `test/xls_statem_mask_reduction_tests.erl`
- `test/xls_statem_plan_tests.erl`
- `test/xls_statem_reduction_codegen_tests.erl`
- `test/xls_statem_reduction_lower_tests.erl`
- `test/xls_static_integer_tests.erl`
- `test/xls_struct_codec_dslx.erl`
- `test/xls_struct_codec_tests.erl`
- `test/xls_topology_family_tests.erl`
- `test/xls_type_shape_dslx.erl`
- `test/xls_type_shape_fixture.erl`
- `test/xls_type_shape_tests.erl`
- `test/xls_type_tests.erl`
- `test/xls_var_scope_tests.erl`
- `test_data/application_frames_rtl.x`
- `test_data/hls_closure_deferred_fixture.erl`
- `test_data/hls_closure_helpers.hrl`
- `test_data/hls_closure_immediate_fixture.erl`
- `test_data/hls_closure_statem_fixture.erl`
- `test_data/hls_closure_types.hrl`
- `test_data/hls_companion_gs_fixture.erl`
- `test_data/hls_companion_provider.x`
- `test_data/hls_companion_types.hrl`
- `test_data/hls_list_reduction_fixture.erl`
- `test_data/hls_names_semantics.inc.x`
- `test_data/hls_numeric_semantics.inc.x`
- `test_data/hls_reduction_failure_head_semantics.inc.x`
- `test_data/hls_reduction_failure_ordinary_semantics.inc.x`
- `test_data/hls_reduction_failure_semantics.inc.x`
- `test_data/hls_shape_type_config.hrl`
- `test_data/hls_shape_type_fixture.erl`
- `test_data/hls_source_context_fixture.erl`
- `test_data/hls_source_context_semantics.inc.x`
- `test_data/hls_statem_mask_debug_semantics.inc.x`
- `test_data/hls_statem_mask_reduction_fixture.erl`
- `test_data/hls_statem_mask_reduction_semantics.inc.x`
- `test_data/hls_statem_reduction_lower_fixture.erl`
- `test_data/hls_statem_reduction_semantics.inc.x`
- `test_data/hls_statem_signed_mask_semantics.inc.x`
- `test_data/hls_tags_fixture.erl`
- `test_data/hls_tags_shared.hrl`
- `test_data/hls_tags_statem_fixture.erl`
- `test_data/hls_type_shape_semantics.inc.x`
- `test_data/spacetime_memory_tb.sv`
- `test_data/xls_case_fixture.erl`
- `test_data/xls_collection_type_repro.x`
- `test_data/xls_control_failure_semantics.inc.x`
- `test_data/xls_entry_branch_semantics.inc.x`
- `test_data/xls_entry_outcome_semantics.inc.x`
- `test_data/xls_entry_reduction_semantics.inc.x`
- `test_data/xls_frame_layout_fixture.erl`
- `test_data/xls_known_bits_probe.inc.x`
- `test_data/xls_message_facts_fixture.erl`
- `test_data/xls_phase_values_probe.inc.x`
- `test_data/xls_selection.x`
- `test_data/xls_srem_overflow_repro.x`
- `test_data/xls_state_updates.x`
- `test_data/xls_statem_event_semantics.inc.x`
- `test_data/xls_statem_gather_debug_semantics.inc.x`
- `test_data/xls_statem_gather_fixture.erl`
- `test_data/xls_statem_gather_semantics.inc.x`
- `test_data/xls_statem_gather_sites_fixture.erl`
- `test_data/xls_statem_gather_sites_semantics.inc.x`
- `test_data/xls_statem_reduction_reply_semantics.inc.x`
- `test_data/xls_statem_reply_semantics.inc.x`
- `tools/check_actor_observation_ports.py`
- `tools/check_debug_memories.py`
- `tools/check_package_boundaries.py`
- `tools/check_rtl_structure.sh`
- `tools/check_source_contracts.py`
- `tools/ci_diagnostics.py`
- `tools/ci_plan.py`
- `tools/compact_build.py`
- `tools/compile_xls.py`
- `tools/compiler_differential.py`
- `tools/compiler_differential_cases.py`
- `tools/dslx_source_contracts.py`
- `tools/erl_hls_tools/__init__.py`
- `tools/erl_hls_tools/compile_xls.py`
- `tools/erl_hls_tools/hls_profile.py`
- `tools/erl_hls_tools/measure_topology_debug.py`
- `tools/erl_hls_tools/package_boundaries.py`
- `tools/erl_hls_tools/testing.py`
- `tools/erl_hls_tools/topology_debug.py`
- `tools/erl_hls_tools/topology_debug_actors.py`
- `tools/erl_hls_tools/topology_debug_report.py`
- `tools/erl_hls_tools/topology_debug_services.py`
- `tools/erl_hls_tools/xls_ir_census.py`
- `tools/hls_profile.py`
- `tools/measure_application_frames.py`
- `tools/measure_direct_actor_debug.py`
- `tools/measure_fabric_router.py`
- `tools/measure_topology_debug.py`
- `tools/prepare_xls_sim.sh`
- `tools/regression_cases.py`
- `tools/regression_inventory.json`
- `tools/regression_inventory.py`
- `tools/regression_steps.py`
- `tools/remote_xls_sim.sh`
- `tools/run_regression.py`
- `tools/run_xls_sim.sh`
- `tools/source_contracts.erl`
- `tools/test_actor_snapshot_formal.py`
- `tools/test_application_frames.sh`
- `tools/test_arbitration.py`
- `tools/test_binary.sh`
- `tools/test_chunked_arithmetic.py`
- `tools/test_ci_diagnostics.py`
- `tools/test_ci_plan.py`
- `tools/test_collections.sh`
- `tools/test_compact_build.py`
- `tools/test_comparisons.sh`
- `tools/test_compile_xls.py`
- `tools/test_compiler_differential.py`
- `tools/test_control_failures.sh`
- `tools/test_debug_memories.py`
- `tools/test_debug_sampling.py`
- `tools/test_debug_trace_integration.py`
- `tools/test_deferred_replies.sh`
- `tools/test_direct_actor_codegen.sh`
- `tools/test_direct_actor_debug.py`
- `tools/test_direct_admission.sh`
- `tools/test_direct_admission_formal.py`
- `tools/test_entry_outcomes.sh`
- `tools/test_fabric_router.py`
- `tools/test_fabric_services.py`
- `tools/test_float_arithmetic.sh`
- `tools/test_helpers.sh`
- `tools/test_hls_profile.py`
- `tools/test_initialization.sh`
- `tools/test_integer_arithmetic.sh`
- `tools/test_integer_shifts.sh`
- `tools/test_logical_types.sh`
- `tools/test_mixed_topology.sh`
- `tools/test_names.sh`
- `tools/test_package_boundaries.py`
- `tools/test_packed_samples.py`
- `tools/test_patterns.sh`
- `tools/test_phase_values.sh`
- `tools/test_reduction_dslx.sh`
- `tools/test_regression.py`
- `tools/test_serial.sh`
- `tools/test_service_contracts.sh`
- `tools/test_sim_bridge.py`
- `tools/test_source_build_executor.py`
- `tools/test_source_context.sh`
- `tools/test_source_contracts.py`
- `tools/test_source_toolchain.py`
- `tools/test_statem_gathers.sh`
- `tools/test_statem_replies.sh`
- `tools/test_topology_debug.py`
- `tools/test_topology_debug_integration.py`
- `tools/test_type_shapes.sh`
- `tools/test_xls_goldens.py`
- `tools/test_xls_ir_census.py`
- `tools/topology_debug.py`
- `tools/topology_debug_report.py`
- `tools/update_xls_goldens.sh`
- `tools/verify_perfetto_profile.py`
- `tools/xls_goldens.sh`
- `tools/xls_ir_census.py`
- `tools/xls_sim.sh`

### erl_hls / hls_runtime

- `apps/hls_runtime/rebar.config`
- `apps/hls_runtime/src/hls_runtime.app.src`

### hls_fabric / hls_fabric

- `.gitattributes`
- `.github/actions/beam-tools/action.yml`
- `.github/actions/diagnostics/action.yml`
- `.github/actions/iverilog/action.yml`
- `.github/actions/rtl-tools/action.yml`
- `.github/actions/rtl-tools/ubuntu.sources`
- `.github/actions/xls-tools/action.yml`
- `.github/workflows/ci.yml`
- `.gitignore`
- `bin/compile-source-build`
- `bin/hls-fabric`
- `bin/hls-repetition`
- `platforms/xc7/.gitignore`
- `platforms/xc7/apio-1.5.x.jsonc`
- `platforms/xc7/application/check_partition_link.escript`
- `platforms/xc7/application/check_repetition_link.escript`
- `platforms/xc7/application/hls-dma.start`
- `platforms/xc7/application/hls_1r1w_ram_zero_model.v`
- `platforms/xc7/application/hls_link_probe_actor.erl`
- `platforms/xc7/application/install_partition_link.sh`
- `platforms/xc7/application/install_repetition_link.sh`
- `platforms/xc7/application/link_board.py`
- `platforms/xc7/application/link_probe_fixture.erl`
- `platforms/xc7/application/partition_debug_route_tb.sv`
- `platforms/xc7/application/partition_link_packets.v`
- `platforms/xc7/application/partition_link_packets_tb.sv`
- `platforms/xc7/application/partition_packet_probe.v`
- `platforms/xc7/application/partition_packet_probe_tb.sv`
- `platforms/xc7/application/reload_repetition_pl.sh`
- `platforms/xc7/application/repetition-network.start`
- `platforms/xc7/application/repetition_link_fixture.erl`
- `platforms/xc7/application/repetition_link_rtl_tb.sv`
- `platforms/xc7/application/repetition_mac_pair_tb.sv`
- `platforms/xc7/application/repetition_packet_pair_tb.sv`
- `platforms/xc7/application/repetition_packet_role_tb.sv`
- `platforms/xc7/application/repetition_role_rtl_tb.sv`
- `platforms/xc7/application/te0715_partition_link_top.v`
- `platforms/xc7/boot/base-reference.json`
- `platforms/xc7/boot/board.py`
- `platforms/xc7/boot/boot.cmd`
- `platforms/xc7/boot/ethernet-external-autoneg.json`
- `platforms/xc7/boot/external-prbs.json`
- `platforms/xc7/boot/patches/bootgen.patch`
- `platforms/xc7/boot/patches/embeddedsw.patch`
- `platforms/xc7/boot/pcs-external.json`
- `platforms/xc7/boot/probe.its`
- `platforms/xc7/boot/reference-images.json`
- `platforms/xc7/boot/reference.py`
- `platforms/xc7/boot/sources.json`
- `platforms/xc7/boot/symbol-external.json`
- `platforms/xc7/bram/boot.cmd`
- `platforms/xc7/bram/bram_probe_tb.sv`
- `platforms/xc7/bram/build_ramb36_sdp72_reference.tcl`
- `platforms/xc7/bram/check_backend.py`
- `platforms/xc7/bram/check_yosys.py`
- `platforms/xc7/bram/nextpnr-ramb36-sdp72.patch`
- `platforms/xc7/bram/probe_bram.c`
- `platforms/xc7/bram/ramb36_sdp72_reference.v`
- `platforms/xc7/bram/te0715_bram_probe.v`
- `platforms/xc7/build_clock_fsbl.py`
- `platforms/xc7/build_link_application.py`
- `platforms/xc7/build_qemu_cosim.py`
- `platforms/xc7/build_regsvc_fsbl.py`
- `platforms/xc7/build_regsvc_rtl.py`
- `platforms/xc7/build_repetition_link_application.py`
- `platforms/xc7/build_te0715_kernel.py`
- `platforms/xc7/check_zynq7030_bitstream.py`
- `platforms/xc7/check_zynq_boot.py`
- `platforms/xc7/clocking/clock_fsbl.c`
- `platforms/xc7/clocking/probe_clock.c`
- `platforms/xc7/clocking/profile.h`
- `platforms/xc7/clocking/profile.py`
- `platforms/xc7/clocking/ps_i2c.c`
- `platforms/xc7/clocking/ps_i2c.h`
- `platforms/xc7/clocking/si5338.c`
- `platforms/xc7/clocking/si5338.h`
- `platforms/xc7/clocking/test_bsp/fsbl.h`
- `platforms/xc7/clocking/test_bsp/sleep.h`
- `platforms/xc7/clocking/test_bsp/xparameters.h`
- `platforms/xc7/clocking/test_clock_fsbl.c`
- `platforms/xc7/clocking/test_ps_i2c.c`
- `platforms/xc7/clocking/test_si5338.c`
- `platforms/xc7/cosim/ethernet-init.sh`
- `platforms/xc7/cosim/ethernet_fixture.sv`
- `platforms/xc7/cosim/guest-init.sh`
- `platforms/xc7/cosim/icarus_bridge.c`
- `platforms/xc7/cosim/mailbox_tb.sv`
- `platforms/xc7/cosim/protocol.h`
- `platforms/xc7/cosim/qemu_bridge.c`
- `platforms/xc7/cosim/qemu_bridge.h`
- `platforms/xc7/cosim/regsvc-init.sh`
- `platforms/xc7/cosim/runtime.py`
- `platforms/xc7/cosim/sources.lock.json`
- `platforms/xc7/dma/builder.lock.json`
- `platforms/xc7/dma/check_dma_beam.escript`
- `platforms/xc7/dma/check_dma_device.c`
- `platforms/xc7/dma/check_regsvc_dma.escript`
- `platforms/xc7/dma/debug_device_tree.py`
- `platforms/xc7/dma/device_tree.py`
- `platforms/xc7/dma/driver/Makefile`
- `platforms/xc7/dma/driver/hls_dma_copy.h`
- `platforms/xc7/dma/driver/hls_dma_mailbox.c`
- `platforms/xc7/dma/driver/hls_dma_selftest.c`
- `platforms/xc7/dma/install-init.sh`
- `platforms/xc7/dma/kernel-build.sh`
- `platforms/xc7/dma/models.lock.json`
- `platforms/xc7/dma/routed_image.py`
- `platforms/xc7/dma/runtime-check.sh`
- `platforms/xc7/dma/zynq_dma_mailbox.v`
- `platforms/xc7/dma/zynq_dma_mailbox_tb.sv`
- `platforms/xc7/dma/zynq_dma_pair.v`
- `platforms/xc7/dma/zynq_dma_pair_tb.sv`
- `platforms/xc7/dma/zynq_dma_top.v`
- `platforms/xc7/dma/zynq_regsvc_core.sv`
- `platforms/xc7/escript_test.py`
- `platforms/xc7/ethernet/LICENSE.liteeth`
- `platforms/xc7/ethernet/LICENSE.litex`
- `platforms/xc7/ethernet/LICENSE.migen`
- `platforms/xc7/ethernet/board.py`
- `platforms/xc7/ethernet/cdc_slot.v`
- `platforms/xc7/ethernet/check_dma_packets.c`
- `platforms/xc7/ethernet/check_dma_peer.c`
- `platforms/xc7/ethernet/clock_pair.v`
- `platforms/xc7/ethernet/dma_board.py`
- `platforms/xc7/ethernet/dma_endpoint.v`
- `platforms/xc7/ethernet/dma_fixture.py`
- `platforms/xc7/ethernet/dma_packets.v`
- `platforms/xc7/ethernet/dma_packets_tb.sv`
- `platforms/xc7/ethernet/dropbear.start`
- `platforms/xc7/ethernet/frame_store.v`
- `platforms/xc7/ethernet/frame_store_tb.sv`
- `platforms/xc7/ethernet/gearbox_packet_fixture.sv`
- `platforms/xc7/ethernet/generate.py`
- `platforms/xc7/ethernet/generate_gearbox.py`
- `platforms/xc7/ethernet/generate_pcs_probe.py`
- `platforms/xc7/ethernet/gtx_clocks.v`
- `platforms/xc7/ethernet/gtx_packet_endpoint.v`
- `platforms/xc7/ethernet/install_dma_peer.sh`
- `platforms/xc7/ethernet/models.lock.json`
- `platforms/xc7/ethernet/packet_endpoint.v`
- `platforms/xc7/ethernet/packet_tb.sv`
- `platforms/xc7/ethernet/pcs_autoneg_tb.sv`
- `platforms/xc7/ethernet/pcs_probe_report.py`
- `platforms/xc7/ethernet/pcs_probe_sample.v`
- `platforms/xc7/ethernet/pcs_probe_tb.sv`
- `platforms/xc7/ethernet/prepare.py`
- `platforms/xc7/ethernet/prepare_pcs_probe.py`
- `platforms/xc7/ethernet/probe_ethernet.c`
- `platforms/xc7/ethernet/probe_pcs.c`
- `platforms/xc7/ethernet/probe_symbols.c`
- `platforms/xc7/ethernet/probe_tb.sv`
- `platforms/xc7/ethernet/probe_traffic.v`
- `platforms/xc7/ethernet/recovery_tb.sv`
- `platforms/xc7/ethernet/reference.py`
- `platforms/xc7/ethernet/snapshot.v`
- `platforms/xc7/ethernet/sources.lock.json`
- `platforms/xc7/ethernet/supervised_endpoint.v`
- `platforms/xc7/ethernet/symbol_probe_sample.v`
- `platforms/xc7/ethernet/symbol_probe_tb.sv`
- `platforms/xc7/ethernet/symbol_report.py`
- `platforms/xc7/ethernet/te0715_ethernet.xdc`
- `platforms/xc7/ethernet/te0715_ethernet_dma_top.v`
- `platforms/xc7/ethernet/te0715_ethernet_top.v`
- `platforms/xc7/ethernet/te0715_pcs_probe_top.v`
- `platforms/xc7/ethernet/te0715_symbol_top.v`
- `platforms/xc7/ethernet/test_probe_pcs.c`
- `platforms/xc7/ethernet/test_probe_symbols.c`
- `platforms/xc7/fetch_regsvc_rtl.sh`
- `platforms/xc7/gtx/.gitattributes`
- `platforms/xc7/gtx/LICENSE.liteiclink`
- `platforms/xc7/gtx/LICENSE.prjxray`
- `platforms/xc7/gtx/assemble.py`
- `platforms/xc7/gtx/build_backend.sh`
- `platforms/xc7/gtx/check_backend.py`
- `platforms/xc7/gtx/clock_cascades.py`
- `platforms/xc7/gtx/compose_external_prbs.py`
- `platforms/xc7/gtx/configuration.lock.json`
- `platforms/xc7/gtx/coverage.py`
- `platforms/xc7/gtx/gtx_probe_control.v`
- `platforms/xc7/gtx/gtx_probe_sample.v`
- `platforms/xc7/gtx/gtx_probe_tb.sv`
- `platforms/xc7/gtx/nextpnr-mmcm-power.patch`
- `platforms/xc7/gtx/nextpnr-refclk.patch`
- `platforms/xc7/gtx/nextpnr-unused-clkin.patch`
- `platforms/xc7/gtx/prepare.py`
- `platforms/xc7/gtx/probe_gtx.c`
- `platforms/xc7/gtx/reference.lock.json`
- `platforms/xc7/gtx/reference.py`
- `platforms/xc7/gtx/report.py`
- `platforms/xc7/gtx/sources.lock.json`
- `platforms/xc7/gtx/te0715_gtx.xdc`
- `platforms/xc7/gtx/te0715_gtx_channel.v`
- `platforms/xc7/gtx/te0715_gtx_lane.v`
- `platforms/xc7/gtx/te0715_gtx_top.v`
- `platforms/xc7/gtx/test_probe_gtx.c`
- `platforms/xc7/initramfs.py`
- `platforms/xc7/lut_legality/build.sh`
- `platforms/xc7/lut_legality/check.py`
- `platforms/xc7/lut_legality/fixed_fixture.v`
- `platforms/xc7/lut_legality/fixture.v`
- `platforms/xc7/lut_legality/nextpnr-output-pin.patch`
- `platforms/xc7/lut_legality/nextpnr-pin-origins.patch`
- `platforms/xc7/lut_legality/test_check.py`
- `platforms/xc7/measure_decoder_profiles.py`
- `platforms/xc7/measure_phi_mapping.py`
- `platforms/xc7/openxc7_common.sh`
- `platforms/xc7/packaging_commands.py`
- `platforms/xc7/phi_compare_tb.sv`
- `platforms/xc7/phi_timing.py`
- `platforms/xc7/phi_timing_harness.v`
- `platforms/xc7/phi_timing_tb.sv`
- `platforms/xc7/prepare_ethernet_dma_peer.py`
- `platforms/xc7/prepare_link_probe.py`
- `platforms/xc7/prepare_partition_link.py`
- `platforms/xc7/prepare_ps_probe.py`
- `platforms/xc7/prepare_sfp_probe.py`
- `platforms/xc7/prepare_te0715_boot.py`
- `platforms/xc7/prepare_te0715_dma.py`
- `platforms/xc7/prepare_te0715_runtime.py`
- `platforms/xc7/prepare_zynq7030.py`
- `platforms/xc7/probe_zynq_ps.c`
- `platforms/xc7/restart_repetition_pair.py`
- `platforms/xc7/run.sh`
- `platforms/xc7/run_ethernet_probe.sh`
- `platforms/xc7/run_gtx_probe.sh`
- `platforms/xc7/run_pcs_probe.sh`
- `platforms/xc7/run_qemu_cosim.py`
- `platforms/xc7/run_regsvc.sh`
- `platforms/xc7/run_sfp_probe.sh`
- `platforms/xc7/run_symbol_probe.sh`
- `platforms/xc7/run_zynq7030.sh`
- `platforms/xc7/run_zynq_dma.sh`
- `platforms/xc7/run_zynq_ps_probe.sh`
- `platforms/xc7/run_zynq_regsvc.sh`
- `platforms/xc7/runtime/bin/runtime-check`
- `platforms/xc7/runtime/boot.cmd`
- `platforms/xc7/runtime/build-init.sh`
- `platforms/xc7/runtime/check-init.sh`
- `platforms/xc7/runtime/check.start`
- `platforms/xc7/runtime/packages.lock.json`
- `platforms/xc7/runtime/runtime.its`
- `platforms/xc7/sfp/probe_sfp.c`
- `platforms/xc7/sfp/record.py`
- `platforms/xc7/sfp/rgpio_reader.v`
- `platforms/xc7/sfp/sfp_eeprom.h`
- `platforms/xc7/sfp/sfp_io.h`
- `platforms/xc7/sfp/sfp_status_tb.sv`
- `platforms/xc7/sfp/te0715_sfp.xdc`
- `platforms/xc7/sfp/te0715_sfp_top.v`
- `platforms/xc7/sfp/test_probe_sfp.c`
- `platforms/xc7/sfp/test_sfp_eeprom.c`
- `platforms/xc7/sfp/vendor/LICENSE`
- `platforms/xc7/sfp/vendor/ddsrpi_slave.v`
- `platforms/xc7/sfp/vendor/ddsrpi_slave.vhd`
- `platforms/xc7/sfp/vendor/source.json`
- `platforms/xc7/smoke.v`
- `platforms/xc7/test_bram_backend.py`
- `platforms/xc7/test_clock_startup.py`
- `platforms/xc7/test_ethernet.py`
- `platforms/xc7/test_ethernet_dma.py`
- `platforms/xc7/test_ethernet_gearbox.py`
- `platforms/xc7/test_ethernet_recovery.py`
- `platforms/xc7/test_gtx_assembly.py`
- `platforms/xc7/test_gtx_probe.py`
- `platforms/xc7/test_link_probe.py`
- `platforms/xc7/test_lut_legality.py`
- `platforms/xc7/test_packaging_support.py`
- `platforms/xc7/test_partition_link.py`
- `platforms/xc7/test_pcs_probe.py`
- `platforms/xc7/test_phi_timing.py`
- `platforms/xc7/test_probe_zynq_ps.c`
- `platforms/xc7/test_ps_probe.py`
- `platforms/xc7/test_qemu_cosim.py`
- `platforms/xc7/test_regsvc_context.py`
- `platforms/xc7/test_repetition_link.py`
- `platforms/xc7/test_restart_repetition_pair.py`
- `platforms/xc7/test_sfp_probe.py`
- `platforms/xc7/test_symbol_probe.py`
- `platforms/xc7/test_te0715_boot.py`
- `platforms/xc7/test_te0715_dma_qemu.py`
- `platforms/xc7/test_te0715_qemu.py`
- `platforms/xc7/test_te0715_runtime.py`
- `platforms/xc7/test_update_fat_macos.py`
- `platforms/xc7/test_vivado.py`
- `platforms/xc7/test_zynq7030.py`
- `platforms/xc7/test_zynq_dma.py`
- `platforms/xc7/test_zynq_ps_probe.py`
- `platforms/xc7/timing_chains/aggregate_boundary.py`
- `platforms/xc7/timing_chains/aggregate_fifo_tb.sv`
- `platforms/xc7/timing_chains/aggregate_traffic.py`
- `platforms/xc7/timing_chains/architecture.py`
- `platforms/xc7/timing_chains/architecture_physical.py`
- `platforms/xc7/timing_chains/architecture_schedule.py`
- `platforms/xc7/timing_chains/architecture_validate.py`
- `platforms/xc7/timing_chains/boundary_experiment.py`
- `platforms/xc7/timing_chains/boundary_trace.py`
- `platforms/xc7/timing_chains/completion_experiment.py`
- `platforms/xc7/timing_chains/completion_fifo_tb.sv`
- `platforms/xc7/timing_chains/completion_storage.py`
- `platforms/xc7/timing_chains/control_cones.py`
- `platforms/xc7/timing_chains/control_frontier.py`
- `platforms/xc7/timing_chains/dedicated_actor.template.x`
- `platforms/xc7/timing_chains/dedicated_egress.v`
- `platforms/xc7/timing_chains/dedicated_egress_tb.sv`
- `platforms/xc7/timing_chains/dependency_report.py`
- `platforms/xc7/timing_chains/dsp_cascade_miter.v`
- `platforms/xc7/timing_chains/egress_experiment.py`
- `platforms/xc7/timing_chains/executor_arrival.py`
- `platforms/xc7/timing_chains/executor_mapping.py`
- `platforms/xc7/timing_chains/factor_rounding.py`
- `platforms/xc7/timing_chains/fifo_experiment.py`
- `platforms/xc7/timing_chains/fifo_probe.py`
- `platforms/xc7/timing_chains/fixtures/bram-endpoint.rpt`
- `platforms/xc7/timing_chains/fixtures/dsp-chain.rpt`
- `platforms/xc7/timing_chains/fixtures/lutram-data-endpoint.rpt`
- `platforms/xc7/timing_chains/fixtures/native-dsp-path.txt`
- `platforms/xc7/timing_chains/fixtures/registered-dsp.rpt`
- `platforms/xc7/timing_chains/fixtures/ultrascale-carry.rpt`
- `platforms/xc7/timing_chains/install_dsp_cascade.py`
- `platforms/xc7/timing_chains/install_path_report.py`
- `platforms/xc7/timing_chains/mailbox_experiment.py`
- `platforms/xc7/timing_chains/mailbox_widths.py`
- `platforms/xc7/timing_chains/module_substitution.py`
- `platforms/xc7/timing_chains/numerical_feedback.py`
- `platforms/xc7/timing_chains/path_report.py`
- `platforms/xc7/timing_chains/phi_numerical.py`
- `platforms/xc7/timing_chains/phi_numerical.x`
- `platforms/xc7/timing_chains/phi_numerical_bank.py`
- `platforms/xc7/timing_chains/phi_numerical_bank.sv`
- `platforms/xc7/timing_chains/phi_numerical_physical.py`
- `platforms/xc7/timing_chains/physical_census.py`
- `platforms/xc7/timing_chains/physical_census.tcl`
- `platforms/xc7/timing_chains/pipeline_ablation.py`
- `platforms/xc7/timing_chains/pipeline_ablation_report.py`
- `platforms/xc7/timing_chains/pipeline_fullness.py`
- `platforms/xc7/timing_chains/pipeline_paths.tcl`
- `platforms/xc7/timing_chains/pipeline_tile.py`
- `platforms/xc7/timing_chains/pipeline_tile_report.py`
- `platforms/xc7/timing_chains/plot.py`
- `platforms/xc7/timing_chains/probe.py`
- `platforms/xc7/timing_chains/prove_fifo.py`
- `platforms/xc7/timing_chains/prove_frame_queue.py`
- `platforms/xc7/timing_chains/prove_rounding.py`
- `platforms/xc7/timing_chains/reciprocal_integration.py`
- `platforms/xc7/timing_chains/replicate.py`
- `platforms/xc7/timing_chains/schedule_report.py`
- `platforms/xc7/timing_chains/scheduled_reciprocal.py`
- `platforms/xc7/timing_chains/selector_experiment.py`
- `platforms/xc7/timing_chains/shared_subchains.py`
- `platforms/xc7/timing_chains/shared_subchains.tcl`
- `platforms/xc7/timing_chains/staged_reciprocal.py`
- `platforms/xc7/timing_chains/staged_reciprocal.x`
- `platforms/xc7/timing_chains/staged_reciprocal_native.py`
- `platforms/xc7/timing_chains/technology_batch.py`
- `platforms/xc7/timing_chains/technology_compare.tcl`
- `platforms/xc7/timing_chains/technology_report.py`
- `platforms/xc7/timing_chains/test_control_cones.py`
- `platforms/xc7/timing_chains/test_control_frontier.py`
- `platforms/xc7/timing_chains/test_dsp_cascade.cc`
- `platforms/xc7/timing_chains/test_dsp_cascade.py`
- `platforms/xc7/timing_chains/test_numerical_feedback.py`
- `platforms/xc7/timing_chains/test_path_report.py`
- `platforms/xc7/timing_chains/test_pipeline_fullness.py`
- `platforms/xc7/timing_chains/test_probe.py`
- `platforms/xc7/timing_chains/test_replicate.py`
- `platforms/xc7/timing_chains/test_technology_batch.py`
- `platforms/xc7/timing_chains/test_technology_report.py`
- `platforms/xc7/timing_chains/test_technology_screen.py`
- `platforms/xc7/timing_chains/width_mapping.py`
- `platforms/xc7/timing_chains/xc7_dsp_cascade.inc`
- `platforms/xc7/timing_coverage/build.sh`
- `platforms/xc7/timing_coverage/check.py`
- `platforms/xc7/timing_coverage/fixture.v`
- `platforms/xc7/timing_coverage/nextpnr-coverage.patch`
- `platforms/xc7/timing_coverage/run.py`
- `platforms/xc7/timing_coverage/test_check.py`
- `platforms/xc7/timing_model/analyze.py`
- `platforms/xc7/timing_model/application.py`
- `platforms/xc7/timing_model/audit_main.cc`
- `platforms/xc7/timing_model/batch.py`
- `platforms/xc7/timing_model/bram_model.inc`
- `platforms/xc7/timing_model/characterize.py`
- `platforms/xc7/timing_model/circuit_audit.tcl`
- `platforms/xc7/timing_model/collect.py`
- `platforms/xc7/timing_model/compare_native.py`
- `platforms/xc7/timing_model/connectivity.py`
- `platforms/xc7/timing_model/dsp_cascades.py`
- `platforms/xc7/timing_model/expand.py`
- `platforms/xc7/timing_model/export_physical.tcl`
- `platforms/xc7/timing_model/fixed_point.ir`
- `platforms/xc7/timing_model/hard_blocks.py`
- `platforms/xc7/timing_model/install_native.py`
- `platforms/xc7/timing_model/install_xls.py`
- `platforms/xc7/timing_model/measure.tcl`
- `platforms/xc7/timing_model/prepare_application.py`
- `platforms/xc7/timing_model/probe_paths.tcl`
- `platforms/xc7/timing_model/ram_modes.py`
- `platforms/xc7/timing_model/report.py`
- `platforms/xc7/timing_model/sdf.py`
- `platforms/xc7/timing_model/selection_shapes.py`
- `platforms/xc7/timing_model/test_codegen.py`
- `platforms/xc7/timing_model/test_dsp_cascades.py`
- `platforms/xc7/timing_model/test_estimator.py`
- `platforms/xc7/timing_model/test_model.py`
- `platforms/xc7/timing_model/test_selection_shapes.py`
- `platforms/xc7/timing_model/validate.py`
- `platforms/xc7/timing_model/validate_kernel.py`
- `platforms/xc7/timing_model/xc7_7030.tsv`
- `platforms/xc7/timing_model/xc7_delay_estimator.cc`
- `platforms/xc7/update_fat_macos.py`
- `platforms/xc7/vivado/build.tcl`
- `platforms/xc7/vivado/cdc.tcl`
- `platforms/xc7/vivado/constraints.tcl`
- `platforms/xc7/vivado/ethernet_serial_tb.sv`
- `platforms/xc7/vivado/evidence.py`
- `platforms/xc7/vivado/gtx_tb.sv`
- `platforms/xc7/vivado/micro.v`
- `platforms/xc7/vivado/prepare.py`
- `platforms/xc7/vivado/refclk.py`
- `platforms/xc7/vivado/simulate.tcl`
- `platforms/xc7/vivado/wizard.tcl`
- `platforms/xc7/write_boot.sh`
- `platforms/xc7/xc7z010clg225.xdc`
- `platforms/xc7/xc7z020clg484.xdc`
- `platforms/xc7/xc7z030sbg485.xdc`
- `platforms/xc7/zynq7030_smoke.v`
- `platforms/xc7/zynq_ps_probe.v`
- `platforms/xc7/zynq_ps_probe.xdc`
- `platforms/xc7/zynq_ps_probe_tb.sv`
- `platforms/xc7/zynq_ps_probe_top.v`
- `rebar.config`
- `rebar.lock`
- `source-contracts.json`
- `src/hls_fabric.app.src`
- `test/formal/async_fifo.sby`
- `test/formal/async_fifo.sv`
- `test/hls_actor_broker_fixture.erl`
- `test/hls_actor_debug_dslx.erl`
- `test/hls_actor_debug_fixture.erl`
- `test/hls_actor_debug_helpers.hrl`
- `test/hls_actor_debug_live.erl`
- `test/hls_actor_pid_dslx.erl`
- `test/hls_actor_pid_fixture.erl`
- `test/hls_actor_pid_live.erl`
- `test/hls_admission_collection_dslx.erl`
- `test/hls_build_diagnostics_tests.erl`
- `test/hls_build_profile_tests.erl`
- `test/hls_carrier_bench.erl`
- `test/hls_ci_snowflake.erl`
- `test/hls_debug_catalog_shared_tests.erl`
- `test/hls_dense_statem_fixture.erl`
- `test/hls_dense_topology_dslx.erl`
- `test/hls_device_fixture.erl`
- `test/hls_device_rtl.erl`
- `test/hls_dma_device_tests.erl`
- `test/hls_fabric_runtime_package_tests.erl`
- `test/hls_generated_files_tests.erl`
- `test/hls_indexed_adapter_dslx.erl`
- `test/hls_indexed_adapter_fixture.erl`
- `test/hls_indexed_adapter_semantics.inc.x`
- `test/hls_indexed_adapter_shape.inc.x`
- `test/hls_indexed_debug_dslx.erl`
- `test/hls_indexed_debug_fixture.erl`
- `test/hls_indexed_debug_live.erl`
- `test/hls_link_diagnostics_tests.erl`
- `test/hls_local_actor_fixture.erl`
- `test/hls_mailbox_debug_fixture.erl`
- `test/hls_mailbox_debug_tests.erl`
- `test/hls_mixed_collector.erl`
- `test/hls_mixed_protocol.hrl`
- `test/hls_mixed_source.erl`
- `test/hls_mixed_topology_dslx.erl`
- `test/hls_mixed_worker.erl`
- `test/hls_node_actor_tests.erl`
- `test/hls_node_tests.erl`
- `test/hls_node_topology_tests.erl`
- `test/hls_partition_fixture.erl`
- `test/hls_partition_ingress_tests.erl`
- `test/hls_partition_link_fixture.erl`
- `test/hls_partition_outbox_tests.erl`
- `test/hls_partition_peer.erl`
- `test/hls_partition_peers_tests.erl`
- `test/hls_partition_reduction_tests.erl`
- `test/hls_partition_retagged_fixture.erl`
- `test/hls_partition_schedule_tests.erl`
- `test/hls_partition_start_tests.erl`
- `test/hls_partition_stream_tests.erl`
- `test/hls_partition_tests.erl`
- `test/hls_partition_tile_debug_tests.erl`
- `test/hls_partition_tile_tests.erl`
- `test/hls_projection_fixture.erl`
- `test/hls_projection_reduction_fixture.erl`
- `test/hls_projection_rounded_fixture.erl`
- `test/hls_projection_wide_fixture.erl`
- `test/hls_protocol_activation_fixture.erl`
- `test/hls_protocol_application_codec_tests.erl`
- `test/hls_protocol_application_conflict.erl`
- `test/hls_protocol_application_live.erl`
- `test/hls_protocol_application_tests.erl`
- `test/hls_protocol_arithmetic_fixture.erl`
- `test/hls_protocol_arithmetic_tests.erl`
- `test/hls_protocol_boundary_fixture.erl`
- `test/hls_protocol_boundary_tests.erl`
- `test/hls_protocol_bridge_live.erl`
- `test/hls_protocol_build_tests.erl`
- `test/hls_protocol_call_fixture.erl`
- `test/hls_protocol_capture_fixture.erl`
- `test/hls_protocol_capture_tests.erl`
- `test/hls_protocol_class_selection_tests.erl`
- `test/hls_protocol_codec_tests.erl`
- `test/hls_protocol_codec_validation.erl`
- `test/hls_protocol_composition_fixture.erl`
- `test/hls_protocol_composition_tests.erl`
- `test/hls_protocol_control_tests.erl`
- `test/hls_protocol_deployment_tests.erl`
- `test/hls_protocol_envelope_tests.erl`
- `test/hls_protocol_fabric_tests.erl`
- `test/hls_protocol_frame_fixture.erl`
- `test/hls_protocol_frame_layout_tests.erl`
- `test/hls_protocol_identity_fixture.erl`
- `test/hls_protocol_identity_fixture.hrl`
- `test/hls_protocol_identity_tests.erl`
- `test/hls_protocol_inbox_fixture.erl`
- `test/hls_protocol_inbox_tests.erl`
- `test/hls_protocol_ingress_fixture.erl`
- `test/hls_protocol_inspection_live.erl`
- `test/hls_protocol_inspection_shapes.erl`
- `test/hls_protocol_inspection_tests.erl`
- `test/hls_protocol_inventory_validation.erl`
- `test/hls_protocol_mixed_admission_actor.erl`
- `test/hls_protocol_mixed_admission_tests.erl`
- `test/hls_protocol_mixed_distribution_fixture.erl`
- `test/hls_protocol_mixed_distribution_tests.erl`
- `test/hls_protocol_mixed_live.erl`
- `test/hls_protocol_mixed_queue_tests.erl`
- `test/hls_protocol_mixed_stream_actor.erl`
- `test/hls_protocol_mixed_stream_tests.erl`
- `test/hls_protocol_mixed_tests.erl`
- `test/hls_protocol_model_tests.erl`
- `test/hls_protocol_network_fixture.erl`
- `test/hls_protocol_network_tests.erl`
- `test/hls_protocol_partition_tests.erl`
- `test/hls_protocol_relay_peer.erl`
- `test/hls_protocol_relay_tests.erl`
- `test/hls_protocol_routing_tests.erl`
- `test/hls_protocol_schema_test_source.erl`
- `test/hls_protocol_startup_fixture.erl`
- `test/hls_protocol_startup_peer.erl`
- `test/hls_protocol_startup_tests.erl`
- `test/hls_protocol_transactions_tests.erl`
- `test/hls_protocol_transport_topology.erl`
- `test/hls_protocol_transport_validation.erl`
- `test/hls_protocol_wait_graph_tests.erl`
- `test/hls_reduction_failure_fixture.erl`
- `test/hls_reduction_plan_branch_fixture.erl`
- `test/hls_reduction_plan_conditional_fixture.erl`
- `test/hls_reduction_plan_excess_fixture.erl`
- `test/hls_reduction_plan_guarded_fixture.erl`
- `test/hls_reduction_plan_inconsistent_fixture.erl`
- `test/hls_reduction_plan_nontransportable_fixture.erl`
- `test/hls_reduction_plan_optional_fixture.erl`
- `test/hls_reduction_plan_population_fixture.erl`
- `test/hls_reduction_plan_refutable_fixture.erl`
- `test/hls_reduction_plan_short_fixture.erl`
- `test/hls_reduction_plan_tests.erl`
- `test/hls_reduction_plan_wrong_schema_fixture.erl`
- `test/hls_retained_host_codec_actor.erl.in`
- `test/hls_retained_host_codec_provider.erl.in`
- `test/hls_retained_host_codec_tests.erl`
- `test/hls_scheduler_build_fixture.erl`
- `test/hls_scheduler_build_tests.erl`
- `test/hls_scheduler_plan_tests.erl`
- `test/hls_shared_reduction_debug_tests.erl`
- `test/hls_source_build_tests.erl`
- `test/hls_statem_event_fixture.erl`
- `test/hls_statem_reduction_fixture.erl`
- `test/hls_statem_reduction_reply_fixture.erl`
- `test/hls_statem_reply_dslx.erl`
- `test/hls_statem_reply_fixture.erl`
- `test/hls_test_nodes.erl`
- `test/hls_topology_constants_tests.erl`
- `test/hls_topology_debug_live.erl`
- `test/hls_topology_ingress_tests.erl`
- `test/hls_topology_layout_fixture.erl`
- `test/hls_topology_reordered_fixture.erl`
- `test/hls_topology_source_fixture.erl`
- `test/hls_topology_source_fragment_fixture.erl`
- `test/hls_topology_source_fragment_port_fixture.erl`
- `test/hls_topology_source_fragment_smoke_fixture.erl`
- `test/local_actor_semantics.x.in`
- `test/local_owner_semantics.x.in`
- `test/local_projection_semantics.x.in`
- `test/local_protocol_properties.x.in`
- `test/protocol_activation_properties.x`
- `test/protocol_egress_cost.x.in`
- `test/protocol_egress_properties.x.in`
- `test/protocol_inbox_properties.x`
- `test/protocol_ingress_properties.x`
- `test/protocol_startup_properties.x`
- `test/rtl/actor_device_tb.sv`
- `test/rtl/admission_collection_tb.sv`
- `test/rtl/aggregate_mux_tb.sv`
- `test/rtl/async_fifo_latency_tb.sv`
- `test/rtl/async_fifo_tb.sv`
- `test/rtl/credit_arbitration_tb.sv`
- `test/rtl/credit_link_fault_tb.sv`
- `test/rtl/credit_link_tb.sv`
- `test/rtl/credit_service_tb.sv`
- `test/rtl/device_services_tb.sv`
- `test/rtl/direct_collection_tb.sv`
- `test/rtl/effect_router_tb.sv.in`
- `test/rtl/effect_router_top.x.in`
- `test/rtl/effect_window_return_tb.sv`
- `test/rtl/effect_window_tb.sv`
- `test/rtl/exclusive_collection_tb.sv`
- `test/rtl/framed_fifo_stream.h`
- `test/rtl/framed_fifo_stream_test.cpp`
- `test/rtl/hls_device_services.sv`
- `test/rtl/hls_indexed_debug.template.v`
- `test/rtl/hls_indexed_gather_ram_tb.sv`
- `test/rtl/hls_reduction_debug.template.v`
- `test/rtl/local_owner_tb.sv`
- `test/rtl/mixed_effect_windows_tb.sv`
- `test/rtl/packed_credit_fault_tb.sv`
- `test/rtl/packed_credit_service_tb.sv`
- `test/rtl/parallel_outbox_actor.x`
- `test/rtl/parallel_outbox_tb.sv`
- `test/rtl/partition_io_tb.sv`
- `test/rtl/partition_ordered_io_tb.sv`
- `test/rtl/partition_peers_tb.sv`
- `test/rtl/partition_reduction_tb.sv`
- `test/rtl/partition_sim_bridge.c`
- `test/rtl/protocol_activation_tb.sv`
- `test/rtl/protocol_application_reset_tb.sv`
- `test/rtl/protocol_application_sim.cpp.in`
- `test/rtl/protocol_arithmetic_tb.sv`
- `test/rtl/protocol_boundary_tb.sv`
- `test/rtl/protocol_bridge_component.x`
- `test/rtl/protocol_bridge_properties.x`
- `test/rtl/protocol_bridge_reset_tb.sv`
- `test/rtl/protocol_bridge_sim.cpp`
- `test/rtl/protocol_bridge_transitions.x`
- `test/rtl/protocol_egress_cost.sv.in`
- `test/rtl/protocol_inbox_tb.sv`
- `test/rtl/protocol_ingress_tb.sv`
- `test/rtl/protocol_inspection_reset_tb.sv`
- `test/rtl/protocol_mixed_sim.cpp`
- `test/rtl/protocol_network_tb.sv`
- `test/rtl/protocol_snowflake_tb.sv`
- `test/rtl/protocol_spacetime_sim.cpp.in`
- `test/rtl/protocol_startup_tb.sv`
- `test/rtl/return_routes_tb.sv`
- `test/rtl/router_probe_actor.x`
- `test/rtl/scheduler_ingress_tb.sv`
- `test/rtl/shared_request_stage_tb.sv`
- `test/rtl/statem_reply_direct_tb.sv`
- `test/rtl/statem_reply_shared_tb.sv`
- `test/rtl/xls_actor_outbox.template.v`
- `test/rtl/xls_actor_outbox_tb.sv`
- `test/rtl/xls_init_topology.template.v`
- `test/rtl/xls_init_topology_tb.sv`
- `test/rtl/xls_scheduler_profile.h`
- `test/rtl/xls_sim_axis.h`
- `test/rtl/xls_sim_bridge.c`
- `test/xls/actor_pid_ingress.x`
- `test/xls/admission_collection.x.in`
- `test/xls/credit_arbitration.x`
- `test/xls/credit_link.x`
- `test/xls/direct_collection.x.in`
- `test/xls/exclusive_collection.x.in`
- `test/xls/machine_row_events.xinc`
- `test/xls/machine_row_gather.xinc`
- `test/xls/machine_row_ordinary.xinc`
- `test/xls/machine_row_projected.xinc`
- `test/xls/machine_row_projected_empty.xinc`
- `test/xls/machine_row_reduction_replies.xinc`
- `test/xls/partition_io.x`
- `test/xls/partition_ordered_io.x`
- `test/xls/partition_reduction_probe.x`
- `test/xls/partition_tile_io.x`
- `test/xls/protocol_envelope_test.x`
- `test/xls/retained_mux_test.x`
- `test/xls/scheduler_ingress_reference.x`
- `test/xls/state_projection_checks.xinc`
- `test/xls_actor_observation_shared_tests.erl`
- `test/xls_actor_outbox_fixture.erl`
- `test/xls_actor_outbox_testgen.erl`
- `test/xls_admission_collection_tests.erl`
- `test/xls_codegen_fixture.erl`
- `test/xls_collection_codegen_tests.erl`
- `test/xls_dslx_imports_shared_tests.erl`
- `test/xls_effect_router_testgen.erl`
- `test/xls_entry_branch_dslx.erl`
- `test/xls_entry_outcome_dslx.erl`
- `test/xls_failure_sites_shared_tests.erl`
- `test/xls_indexed_collection_tests.erl`
- `test/xls_init_dslx.erl`
- `test/xls_init_gs_fixture.erl`
- `test/xls_init_statem_fixture.erl`
- `test/xls_local_execution_tests.erl`
- `test/xls_local_execution_validation.erl`
- `test/xls_machine_layout_tests.erl`
- `test/xls_machine_names_tests.erl`
- `test/xls_names_dslx.erl`
- `test/xls_names_fixture.erl`
- `test/xls_names_gs_fixture.erl`
- `test/xls_parse_shared_tests.erl`
- `test/xls_prepared_scheduler_tests.erl`
- `test/xls_protocol_bits_tests.erl`
- `test/xls_protocol_inbox_tests.erl`
- `test/xls_protocol_transport_tests.erl`
- `test/xls_publication_codegen_tests.erl`
- `test/xls_scheduler_ram_v_tests.erl`
- `test/xls_scheduler_reduction_lower_tests.erl`
- `test/xls_statem_reduction_codegen_shared_tests.erl`
- `test/xls_statem_reduction_service_codegen_tests.erl`
- `test/xls_template_tests.erl`
- `test/xls_topology_effect_windows_tests.erl`
- `test/xls_topology_family_shared_tests.erl`
- `test/xls_topology_mixed_tests.erl`
- `test/xls_topology_profile_tests.erl`
- `test/xls_topology_scheduler_plan_tests.erl`
- `test/xls_topology_source_fragment_dslx_tests.erl`
- `test/xls_type_shape_dslx.erl`
- `test/xls_type_shape_fixture.erl`
- `test_data/effect_window_large.x`
- `test_data/effect_window_rtl.x`
- `test_data/hls_list_reduction_fixture.erl`
- `test_data/hls_names_semantics.inc.x`
- `test_data/hls_reduction_failure_aggregate_semantics.inc.x`
- `test_data/hls_reduction_failure_head_semantics.inc.x`
- `test_data/hls_reduction_failure_ordinary_semantics.inc.x`
- `test_data/hls_reduction_failure_semantics.inc.x`
- `test_data/hls_shape_type_config.hrl`
- `test_data/hls_shape_type_fixture.erl`
- `test_data/hls_statem_reduction_aggregate_semantics.inc.x`
- `test_data/hls_statem_reduction_lower_fixture.erl`
- `test_data/hls_statem_reduction_semantics.inc.x`
- `test_data/hls_tags_shared.hrl`
- `test_data/hls_tags_statem_fixture.erl`
- `test_data/hls_topology_source_fragment_population_semantics.inc.x`
- `test_data/hls_topology_source_fragment_semantics.inc.x`
- `test_data/hls_type_shape_semantics.inc.x`
- `test_data/mailbox_refinement.x`
- `test_data/shared_capture_large.x`
- `test_data/shared_completion_reference.inc.x`
- `test_data/xls_entry_branch_fixture.erl`
- `test_data/xls_entry_branch_semantics.inc.x`
- `test_data/xls_entry_outcome_fixture.erl`
- `test_data/xls_entry_outcome_semantics.inc.x`
- `test_data/xls_entry_reduction_fixture.erl`
- `test_data/xls_entry_reduction_semantics.inc.x`
- `test_data/xls_statem_event_semantics.inc.x`
- `test_data/xls_statem_reduction_reply_semantics.inc.x`
- `test_data/xls_statem_reply_semantics.inc.x`
- `tools/actor_build_artifacts.py`
- `tools/artifacts.py`
- `tools/backend_build_profile.py`
- `tools/backend_commands.py`
- `tools/backend_env.sh`
- `tools/backend_paths.py`
- `tools/bench_carrier.py`
- `tools/check_application_boundaries.py`
- `tools/check_package_boundaries.py`
- `tools/check_source_contracts.py`
- `tools/ci.sh`
- `tools/ci_diagnostics.py`
- `tools/ci_unit_tests.txt`
- `tools/compile_backend.py`
- `tools/compile_local_actor.py`
- `tools/compiler_paths.py`
- `tools/completion_fifo.py`
- `tools/dslx_source_contracts.py`
- `tools/emit_local_actor.escript`
- `tools/emit_local_actor.sh`
- `tools/emit_protocol_application.sh`
- `tools/emit_protocol_boundary.sh`
- `tools/emit_protocol_bridge.sh`
- `tools/emit_protocol_network.sh`
- `tools/emit_protocol_transport.sh`
- `tools/link_service_witness.py`
- `tools/measure_actor_ingress.py`
- `tools/measure_clock_crossings.py`
- `tools/measure_credit_link.py`
- `tools/measure_mixed_windows.py`
- `tools/measure_packed_handoff.py`
- `tools/measure_return_routes.py`
- `tools/prepare_xls_sim.sh`
- `tools/profile_interfaces.escript`
- `tools/profile_views.py`
- `tools/protocol_inspection_sim.py`
- `tools/protocol_test_build.py`
- `tools/remote_xls_sim.sh`
- `tools/run_xls_sim.sh`
- `tools/scheduler_ram_configurations.sh`
- `tools/source_contracts.erl`
- `tools/test_actor_debug.sh`
- `tools/test_actor_outboxes.sh`
- `tools/test_actor_rtl.py`
- `tools/test_admission_collection.sh`
- `tools/test_admission_collection_rtl.sh`
- `tools/test_aggregate_mux.py`
- `tools/test_async_fifo.py`
- `tools/test_backend_build_profile.py`
- `tools/test_backend_context.py`
- `tools/test_ci_components.py`
- `tools/test_ci_diagnostics.py`
- `tools/test_ci_policy.py`
- `tools/test_compile_local_actor.py`
- `tools/test_credit_arbitration.py`
- `tools/test_credit_link.py`
- `tools/test_credit_service.py`
- `tools/test_direct_collection.py`
- `tools/test_direct_collection_boundary.py`
- `tools/test_effect_router.py`
- `tools/test_effect_window.sh`
- `tools/test_entry_outcomes.sh`
- `tools/test_indexed_collection.sh`
- `tools/test_indexed_debug.sh`
- `tools/test_initialization.sh`
- `tools/test_local_actor.py`
- `tools/test_local_dist.sh`
- `tools/test_local_execution.sh`
- `tools/test_local_owner.py`
- `tools/test_local_protocol.py`
- `tools/test_logical_types.sh`
- `tools/test_mailbox_formal.py`
- `tools/test_mixed_topology.sh`
- `tools/test_names.sh`
- `tools/test_packaging.py`
- `tools/test_packed_credit.py`
- `tools/test_packed_credit_cases.py`
- `tools/test_parallel_outbox.py`
- `tools/test_partition_io.py`
- `tools/test_partition_peers.py`
- `tools/test_partition_reduction.py`
- `tools/test_profile_views.py`
- `tools/test_protocol_activation.py`
- `tools/test_protocol_application.py`
- `tools/test_protocol_arithmetic.py`
- `tools/test_protocol_boundary.py`
- `tools/test_protocol_bridge.py`
- `tools/test_protocol_codecs.sh`
- `tools/test_protocol_inbox.py`
- `tools/test_protocol_ingress.py`
- `tools/test_protocol_inspection_shapes.py`
- `tools/test_protocol_network.py`
- `tools/test_protocol_partition.py`
- `tools/test_protocol_snowflake.py`
- `tools/test_protocol_startup.py`
- `tools/test_protocol_transport.py`
- `tools/test_protocol_transport.sh`
- `tools/test_reduction_dslx.sh`
- `tools/test_return_routes.sh`
- `tools/test_rtl.py`
- `tools/test_scheduler_ingress.py`
- `tools/test_shared_completion.py`
- `tools/test_shared_request_stage.py`
- `tools/test_source_contracts.py`
- `tools/test_source_protocol.sh`
- `tools/test_source_toolchain.py`
- `tools/test_state_projection.sh`
- `tools/test_statem_replies.sh`
- `tools/test_topology_debug_integration.py`
- `tools/test_transport_codegen.py`
- `tools/test_type_shapes.sh`
- `tools/transport_codegen.py`
- `tools/xls_ram_codegen/build.py`
- `tools/xls_ram_codegen/install.py`
- `tools/xls_ram_codegen/manifest.json`
- `tools/xls_ram_codegen/ram-response.patch`
- `tools/xls_ram_codegen/test_install.py`
- `yap/retired-experiments-01-06.json`

### hls_fabric / hls_lowering

- `apps/hls_lowering/priv/rtl/hls_async_fifo.v`
- `apps/hls_lowering/priv/rtl/hls_indexed_gather_ram.v`
- `apps/hls_lowering/priv/rtl/hls_partition_activation.sv`
- `apps/hls_lowering/priv/rtl/hls_return_routes.v`
- `apps/hls_lowering/priv/xls/hls_credit_link.x`
- `apps/hls_lowering/priv/xls/hls_packed_link.x`
- `apps/hls_lowering/priv/xls/hls_partition_io.x`
- `apps/hls_lowering/priv/xls/hls_partition_tile_io.x`
- `apps/hls_lowering/priv/xls/hls_reduction_fragments.x`
- `apps/hls_lowering/priv/xls/lib/effect_window.x`
- `apps/hls_lowering/priv/xls/lib/frame_queue.x`
- `apps/hls_lowering/priv/xls/lib/indexed_collection_core.x`
- `apps/hls_lowering/priv/xls/lib/indexed_gather_ram.x`
- `apps/hls_lowering/priv/xls/lib/mailbox.x`
- `apps/hls_lowering/priv/xls/lib/protocol_activation.x`
- `apps/hls_lowering/priv/xls/lib/protocol_bridge.x`
- `apps/hls_lowering/priv/xls/lib/protocol_egress.x`
- `apps/hls_lowering/priv/xls/lib/protocol_envelope.x`
- `apps/hls_lowering/priv/xls/lib/protocol_framing.x`
- `apps/hls_lowering/priv/xls/lib/protocol_inbox.x`
- `apps/hls_lowering/priv/xls/lib/protocol_ingress.x`
- `apps/hls_lowering/priv/xls/lib/protocol_partition.x`
- `apps/hls_lowering/priv/xls/lib/protocol_rectangle.x`
- `apps/hls_lowering/priv/xls/lib/protocol_startup.x`
- `apps/hls_lowering/priv/xls/lib/protocol_transport.x`
- `apps/hls_lowering/priv/xls/lib/retained_mux.x`
- `apps/hls_lowering/priv/xls/lib/scheduler.x`
- `apps/hls_lowering/priv/xls/lib/scheduler_observation.x`
- `apps/hls_lowering/priv/xls/parallel_outbox.x.in`
- `apps/hls_lowering/priv/xls/partition_reduction.x.in`
- `apps/hls_lowering/priv/xls/scheduler_ingress.x.in`
- `apps/hls_lowering/priv/xls/templates/actor_outboxes.x`
- `apps/hls_lowering/priv/xls/templates/collection_ownership.x`
- `apps/hls_lowering/priv/xls/templates/collection_selected_input.x.in`
- `apps/hls_lowering/priv/xls/templates/direct_collection.x`
- `apps/hls_lowering/priv/xls/templates/direct_collection_service.x.in`
- `apps/hls_lowering/priv/xls/templates/exclusive_collection.x`
- `apps/hls_lowering/priv/xls/templates/exclusive_collection_core.x`
- `apps/hls_lowering/priv/xls/templates/exclusive_collection_fields.x.in`
- `apps/hls_lowering/priv/xls/templates/indexed_collection.x.in`
- `apps/hls_lowering/priv/xls/templates/indexed_collection_admission_reference.x`
- `apps/hls_lowering/priv/xls/templates/indexed_collection_core_tests.x`
- `apps/hls_lowering/priv/xls/templates/indexed_collection_model.x`
- `apps/hls_lowering/priv/xls/templates/indexed_collection_opening_reference.x`
- `apps/hls_lowering/priv/xls/templates/indexed_owner.x.in`
- `apps/hls_lowering/priv/xls/templates/local_arithmetic.x.in`
- `apps/hls_lowering/priv/xls/templates/local_arithmetic_owner.x.in`
- `apps/hls_lowering/priv/xls/templates/local_execution.x.in`
- `apps/hls_lowering/priv/xls/templates/local_inbox.x.in`
- `apps/hls_lowering/priv/xls/templates/local_owner.x.in`
- `apps/hls_lowering/priv/xls/templates/local_owner_import.x.in`
- `apps/hls_lowering/priv/xls/templates/local_protocol.x.in`
- `apps/hls_lowering/priv/xls/templates/local_protocol_gather.x.in`
- `apps/hls_lowering/priv/xls/templates/local_protocol_scalar.x.in`
- `apps/hls_lowering/priv/xls/templates/local_slow.x.in`
- `apps/hls_lowering/priv/xls/templates/local_slow_gather.x.in`
- `apps/hls_lowering/priv/xls/templates/parallel_effect_router.x.in`
- `apps/hls_lowering/priv/xls/templates/protocol_application.x`
- `apps/hls_lowering/priv/xls/templates/protocol_boundary.x.in`
- `apps/hls_lowering/priv/xls/templates/protocol_boundary_clock.x.in`
- `apps/hls_lowering/priv/xls/templates/protocol_bridge.x.in`
- `apps/hls_lowering/priv/xls/templates/protocol_clock.x.in`
- `apps/hls_lowering/priv/xls/templates/protocol_ingress.x.in`
- `apps/hls_lowering/priv/xls/templates/protocol_network.x.in`
- `apps/hls_lowering/priv/xls/templates/protocol_network_clock.x.in`
- `apps/hls_lowering/priv/xls/templates/protocol_transport_link.x.in`
- `apps/hls_lowering/priv/xls/templates/protocol_transport_source.x.in`
- `apps/hls_lowering/priv/xls/templates/scheduler_control.x.in`
- `apps/hls_lowering/priv/xls/templates/scheduler_effect_router.x.in`
- `apps/hls_lowering/priv/xls/templates/scheduler_startup.x.in`
- `apps/hls_lowering/priv/xls/templates/shared_collection.x`
- `apps/hls_lowering/priv/xls/templates/shared_loader.x.in`
- `apps/hls_lowering/priv/xls/templates/shared_service.x.in`
- `apps/hls_lowering/priv/xls/templates/source_fragment_plane.x.in`
- `apps/hls_lowering/src/examples/counter/scheduler-ram.config`
- `apps/hls_lowering/src/examples/counter/scheduler.config`
- `apps/hls_lowering/src/examples/counter/source.config`
- `apps/hls_lowering/src/hls_lowering.app.src`

### hls_fabric / hls_phi

- `apps/hls_phi/include/phenom_data_cell_impl.hrl`
- `apps/hls_phi/include/phenom_syndrome_cell_impl.hrl`
- `apps/hls_phi/include/phi_halo_cell_impl.hrl`
- `apps/hls_phi/include/phi_neighborhood.hrl`
- `apps/hls_phi/include/phi_protocol.hrl`
- `apps/hls_phi/priv/rtl/phi_decoder_profile_top.template.v`
- `apps/hls_phi/priv/rtl/phi_memory_application.template.v`
- `apps/hls_phi/priv/rtl/phi_memory_debug_top.template.v`
- `apps/hls_phi/priv/rtl/phi_memory_top.template.v`
- `apps/hls_phi/src/hls_phi.app.src`
- `apps/hls_phi/src/phenom_data_cell.erl.x`
- `apps/hls_phi/src/phenom_syndrome_cell.erl.x`
- `apps/hls_phi/src/phi_field.x`
- `apps/hls_phi/src/phi_halo_cell.erl.x`
- `apps/hls_phi/src/phi_memory_gateway.x`
- `apps/hls_phi/src/phi_noise_topology.x`
- `apps/hls_phi/src/phi_phenom_topology.x`
- `apps/hls_phi/src/phi_torus_topology.x`
- `apps/hls_phi/test/fabric_peer.py`
- `apps/hls_phi/test/hls_bridge_phi_fixture.erl`
- `apps/hls_phi/test/hls_bridge_phi_fixture_tests.erl`
- `apps/hls_phi/test/hls_bridge_phi_live.erl`
- `apps/hls_phi/test/hls_pauli_tests.erl`
- `apps/hls_phi/test/hls_phi_board_geometry.erl`
- `apps/hls_phi/test/hls_phi_board_geometry_tests.erl`
- `apps/hls_phi/test/hls_phi_debug_dslx.erl`
- `apps/hls_phi/test/hls_phi_debug_live.erl`
- `apps/hls_phi/test/hls_phi_memory_fixture.erl`
- `apps/hls_phi/test/hls_phi_memory_fixture_tests.erl`
- `apps/hls_phi/test/hls_phi_memory_live.erl`
- `apps/hls_phi/test/hls_phi_memory_metrics.erl`
- `apps/hls_phi/test/hls_phi_memory_profile.erl`
- `apps/hls_phi/test/hls_phi_memory_reset.erl`
- `apps/hls_phi/test/hls_phi_profile_debug.erl`
- `apps/hls_phi/test/phenom_data_cell_tests.erl`
- `apps/hls_phi/test/phenom_pipeline_tests.erl`
- `apps/hls_phi/test/phenom_syndrome_cell_tests.erl`
- `apps/hls_phi/test/phi_decoder_profile_build_tests.erl`
- `apps/hls_phi/test/phi_decoder_profile_fixture.erl`
- `apps/hls_phi/test/phi_decoder_profile_topology_tests.erl`
- `apps/hls_phi/test/phi_field_dslx.erl`
- `apps/hls_phi/test/phi_field_tests.erl`
- `apps/hls_phi/test/phi_halo_cell_tests.erl`
- `apps/hls_phi/test/phi_memory_bridge_tests.erl`
- `apps/hls_phi/test/phi_memory_cpu_fabric_tests.erl`
- `apps/hls_phi/test/phi_memory_experiment_tests.erl`
- `apps/hls_phi/test/phi_memory_fabric_fixture.erl`
- `apps/hls_phi/test/phi_memory_gateway_dslx_tests.erl`
- `apps/hls_phi/test/phi_memory_runner_tests.erl`
- `apps/hls_phi/test/phi_memory_wire_tests.erl`
- `apps/hls_phi/test/phi_noise_topology_tests.erl`
- `apps/hls_phi/test/phi_protocol_deployment_live.erl`
- `apps/hls_phi/test/phi_protocol_model_tests.erl`
- `apps/hls_phi/test/phi_protocol_repetition_fixture.erl`
- `apps/hls_phi/test/phi_protocol_repetition_tests.erl`
- `apps/hls_phi/test/phi_repetition_fixture.erl`
- `apps/hls_phi/test/phi_repetition_memory_tests.erl`
- `apps/hls_phi/test/phi_repetition_tests.erl`
- `apps/hls_phi/test/phi_runner_backpressure_tests.erl`
- `apps/hls_phi/test/phi_source_hls_actor_interface_tests.erl`
- `apps/hls_phi/test/phi_source_hls_debug_catalog_tests.erl`
- `apps/hls_phi/test/phi_source_hls_parametric_topology_tests.erl`
- `apps/hls_phi/test/phi_source_hls_topology_tests.erl`
- `apps/hls_phi/test/phi_source_phi_memory_bridge_tests.erl`
- `apps/hls_phi/test/phi_source_xls_parse_tests.erl`
- `apps/hls_phi/test/phi_source_xls_topology_family_tests.erl`
- `apps/hls_phi/test/phi_spacetime_fixture.erl`
- `apps/hls_phi/test/phi_syndrome_replay_cell_tests.erl`
- `apps/hls_phi/test/rtl/debug/hls_phi_debug_live_tb.sv`
- `apps/hls_phi/test/rtl/phenom_data_cell_tb.sv`
- `apps/hls_phi/test/rtl/phi_bridge_tb.sv`
- `apps/hls_phi/test/rtl/phi_cycle_trace_tb.sv`
- `apps/hls_phi/test/rtl/phi_decoder_profile_tb.sv`
- `apps/hls_phi/test/rtl/phi_halo_cell_tb.sv`
- `apps/hls_phi/test/rtl/phi_link_delay.svh`
- `apps/hls_phi/test/rtl/phi_memory_bridge_tb.sv`
- `apps/hls_phi/test/rtl/phi_memory_profile.svh`
- `apps/hls_phi/test/rtl/phi_memory_transport.svh`
- `apps/hls_phi/test/rtl/phi_mesh_tb.sv`
- `apps/hls_phi/test/rtl/phi_noise_topology_smoke_tb.sv`
- `apps/hls_phi/test/rtl/phi_noise_topology_tb.sv`
- `apps/hls_phi/test/rtl/phi_phenom_topology_tb.sv`
- `apps/hls_phi/test/rtl/phi_profile_trace.c`
- `apps/hls_phi/test/rtl/phi_repetition_tb.sv`
- `apps/hls_phi/test/rtl/phi_service_trace.c`
- `apps/hls_phi/test/rtl/phi_source_phi_repetition_tb.sv`
- `apps/hls_phi/test/rtl/phi_torus_topology_tb.sv`
- `apps/hls_phi/tools/build_phi_debug.py`
- `apps/hls_phi/tools/check_dedicated_noise.sh`
- `apps/hls_phi/tools/compile_phi_decoder_profile.py`
- `apps/hls_phi/tools/compile_phi_decoder_profile.sh`
- `apps/hls_phi/tools/decoder_profile_witness.py`
- `apps/hls_phi/tools/emit_protocol_repetition.py`
- `apps/hls_phi/tools/inspect_phi_protocol.escript`
- `apps/hls_phi/tools/inspect_phi_protocol.sh`
- `apps/hls_phi/tools/local_phi_memory_demo.sh`
- `apps/hls_phi/tools/measure_phi_debug.py`
- `apps/hls_phi/tools/measure_phi_memory.py`
- `apps/hls_phi/tools/measure_phi_mesh.py`
- `apps/hls_phi/tools/phi_actor_profile.py`
- `apps/hls_phi/tools/phi_build_artifacts.py`
- `apps/hls_phi/tools/phi_capture.py`
- `apps/hls_phi/tools/phi_cycle_trace.py`
- `apps/hls_phi/tools/phi_decoder_profile_stage.sh`
- `apps/hls_phi/tools/phi_device_build.py`
- `apps/hls_phi/tools/phi_link_packet.py`
- `apps/hls_phi/tools/phi_mailbox_model.py`
- `apps/hls_phi/tools/phi_mailbox_profile.py`
- `apps/hls_phi/tools/phi_mailbox_report.py`
- `apps/hls_phi/tools/phi_mailbox_routes.py`
- `apps/hls_phi/tools/phi_mailbox_trace.py`
- `apps/hls_phi/tools/phi_mesh_build.py`
- `apps/hls_phi/tools/phi_mesh_components.py`
- `apps/hls_phi/tools/phi_mesh_metrics.py`
- `apps/hls_phi/tools/phi_message_profile.py`
- `apps/hls_phi/tools/phi_message_report.py`
- `apps/hls_phi/tools/phi_message_trace.py`
- `apps/hls_phi/tools/phi_packed_metrics.py`
- `apps/hls_phi/tools/phi_profile_phases.py`
- `apps/hls_phi/tools/phi_profile_timeline.py`
- `apps/hls_phi/tools/phi_reduction_profile.py`
- `apps/hls_phi/tools/phi_service_analysis.py`
- `apps/hls_phi/tools/phi_service_metrics.py`
- `apps/hls_phi/tools/phi_step_report.py`
- `apps/hls_phi/tools/phi_tiles.py`
- `apps/hls_phi/tools/phi_tool_paths.py`
- `apps/hls_phi/tools/phi_transport_metrics.py`
- `apps/hls_phi/tools/plot_phi_service.py`
- `apps/hls_phi/tools/plot_phi_transport.py`
- `apps/hls_phi/tools/profile_phi_memory.py`
- `apps/hls_phi/tools/profile_phi_mesh.py`
- `apps/hls_phi/tools/remote_phi_memory_demo.sh`
- `apps/hls_phi/tools/remote_phi_noise_topology_sim.sh`
- `apps/hls_phi/tools/run_phi_decoder_profile.sh`
- `apps/hls_phi/tools/run_phi_memory_demo.sh`
- `apps/hls_phi/tools/run_phi_noise_topology_sim.sh`
- `apps/hls_phi/tools/run_repetition_profile.py`
- `apps/hls_phi/tools/test_debug_build_policy.py`
- `apps/hls_phi/tools/test_decoder_profiles.py`
- `apps/hls_phi/tools/test_phi_actor_profile.py`
- `apps/hls_phi/tools/test_phi_bridge.py`
- `apps/hls_phi/tools/test_phi_build_artifacts.py`
- `apps/hls_phi/tools/test_phi_capture.py`
- `apps/hls_phi/tools/test_phi_cycle_trace.py`
- `apps/hls_phi/tools/test_phi_debug.py`
- `apps/hls_phi/tools/test_phi_device_build.py`
- `apps/hls_phi/tools/test_phi_link_packet.py`
- `apps/hls_phi/tools/test_phi_mailbox_profile.py`
- `apps/hls_phi/tools/test_phi_memory.py`
- `apps/hls_phi/tools/test_phi_mesh.py`
- `apps/hls_phi/tools/test_phi_mesh_components.py`
- `apps/hls_phi/tools/test_phi_mesh_metrics.py`
- `apps/hls_phi/tools/test_phi_message_report.py`
- `apps/hls_phi/tools/test_phi_message_trace.py`
- `apps/hls_phi/tools/test_phi_packed_metrics.py`
- `apps/hls_phi/tools/test_phi_profile_adapter.py`
- `apps/hls_phi/tools/test_phi_profile_phases.py`
- `apps/hls_phi/tools/test_phi_reduction_profile.py`
- `apps/hls_phi/tools/test_phi_service_metrics.py`
- `apps/hls_phi/tools/test_phi_simulation.py`
- `apps/hls_phi/tools/test_phi_step_report.py`
- `apps/hls_phi/tools/test_phi_tiles.py`
- `apps/hls_phi/tools/test_phi_transport_metrics.py`
- `apps/hls_phi/tools/test_pipeline_ablation.py`
- `apps/hls_phi/tools/test_profile_compilation.py`
- `apps/hls_phi/tools/test_protocol_deployment.py`
- `apps/hls_phi/tools/test_protocol_inspection.py`
- `apps/hls_phi/tools/test_protocol_mixed.py`
- `apps/hls_phi/tools/test_protocol_repetition.py`
- `apps/hls_phi/tools/test_verify_phi_components.py`
- `apps/hls_phi/tools/verify_phi_components.py`

### hls_fabric / hls_snowflake

- `apps/hls_snowflake/include/snowflake_actor_protocol.hrl`
- `apps/hls_snowflake/include/snowflake_barrier.hrl`
- `apps/hls_snowflake/include/snowflake_node.hrl`
- `apps/hls_snowflake/include/snowflake_node_impl.hrl`
- `apps/hls_snowflake/priv/fixtures/d3-p005-seed0-first128.json`
- `apps/hls_snowflake/priv/fixtures/enumerated.json`
- `apps/hls_snowflake/priv/fixtures/named.json`
- `apps/hls_snowflake/priv/fixtures/provenance.json`
- `apps/hls_snowflake/priv/fixtures/surface-enumerated.json`
- `apps/hls_snowflake/priv/fixtures/surface-named.json`
- `apps/hls_snowflake/priv/fixtures/surface-provenance.json`
- `apps/hls_snowflake/reference/LICENSE.localuf`
- `apps/hls_snowflake/reference/generate.py`
- `apps/hls_snowflake/reference/generate_surface.py`
- `apps/hls_snowflake/reference/noise_sweep.py`
- `apps/hls_snowflake/reference/requirements.lock`
- `apps/hls_snowflake/reference/scaling_fixtures.py`
- `apps/hls_snowflake/src/hls_snowflake.app.src`
- `apps/hls_snowflake/test/snowflake_actor_tests.erl`
- `apps/hls_snowflake/test/snowflake_barrier_tests.erl`
- `apps/hls_snowflake/test/snowflake_barrier_tests.inc.x`
- `apps/hls_snowflake/test/snowflake_coordinator_tests.erl`
- `apps/hls_snowflake/test/snowflake_local_advance_tests.erl`
- `apps/hls_snowflake/test/snowflake_phase_witness.erl`
- `apps/hls_snowflake/test/snowflake_placement_tests.erl`
- `apps/hls_snowflake/test/snowflake_source_tests.erl`
- `apps/hls_snowflake/test/snowflake_vertex_tests.erl`
- `apps/hls_snowflake/test/snowflake_window_tests.erl`

### hls_fabric / hls_spacetime_protocol

- `apps/hls_spacetime_protocol/src/hls_spacetime_protocol.app.src`
- `apps/hls_spacetime_protocol/test/xls_protocol_spacetime_capture_tests.erl`
- `apps/hls_spacetime_protocol/test/xls_protocol_spacetime_identity_tests.erl`

### hls_spacetime / hls_spacetime

- `.gitignore`
- `package.json`
- `priv/include/spacetime_trace.h`
- `priv/tools/export_route_graph.tcl`
- `priv/tools/export_routes.tcl`
- `priv/tools/export_spacetime.tcl`
- `priv/tools/route_hash_worker.py`
- `priv/tools/route_hash_worker.tcl`
- `rebar.config`
- `rebar.lock`
- `scripts/attach-computations.mjs`
- `scripts/attach-routes.mjs`
- `scripts/check-storage-view.mjs`
- `scripts/observation-revision.mjs`
- `scripts/predict-latency.mjs`
- `scripts/prepare-computations.mjs`
- `scripts/prepare-example.mjs`
- `scripts/prepare-regions.mjs`
- `scripts/prepare-render.mjs`
- `scripts/prepare-view.mjs`
- `scripts/replay-control.mjs`
- `scripts/report-timing.mjs`
- `scripts/select-routes.mjs`
- `scripts/serve.mjs`
- `scripts/timing-paths.mjs`
- `src/hls_spacetime.app.src`
- `test-js/action-chain.test.js`
- `test-js/annotations.test.js`
- `test-js/arrival-circuits.test.js`
- `test-js/arrival-events.test.js`
- `test-js/arrival-layout.test.js`
- `test-js/arrival-ruler.test.js`
- `test-js/arrival-scene.test.js`
- `test-js/attach-computations.test.js`
- `test-js/attach-routes.test.js`
- `test-js/camera3d.test.js`
- `test-js/candidate-cut.test.js`
- `test-js/capture-extension.test.js`
- `test-js/circuit-display.test.js`
- `test-js/clock-reference.test.js`
- `test-js/clock-sink.test.js`
- `test-js/clocked-host.test.js`
- `test-js/clocked-owner.test.js`
- `test-js/clocked-resources.test.js`
- `test-js/clocked-transport.test.js`
- `test-js/computation-loader.test.js`
- `test-js/computation-routes.test.js`
- `test-js/computation-view.test.js`
- `test-js/control-replay.test.js`
- `test-js/fixtures/computation-publication.js`
- `test-js/fixtures/control-profile.json`
- `test-js/footprint.test.js`
- `test-js/labels.test.js`
- `test-js/latency-scenario.test.js`
- `test-js/metrics.test.js`
- `test-js/model.test.js`
- `test-js/native-paths.test.js`
- `test-js/native-routes.test.js`
- `test-js/neighborhood-scene.test.js`
- `test-js/observation-revision.test.js`
- `test-js/overlay-display.test.js`
- `test-js/paint-cache.test.js`
- `test-js/path-explorer.test.js`
- `test-js/path-neighborhood.test.js`
- `test-js/perceptual-color.test.js`
- `test-js/predict-latency.test.js`
- `test-js/prepare-computations.test.js`
- `test-js/prepare-regions.test.js`
- `test-js/prepare-render.test.js`
- `test-js/prepare-view.test.js`
- `test-js/prepared-computations.test.js`
- `test-js/prepared-loader.test.js`
- `test-js/recorded-scenario.test.js`
- `test-js/regional-controls.test.js`
- `test-js/regional-data.test.js`
- `test-js/regional-loader.test.js`
- `test-js/regional-view.test.js`
- `test-js/replay-control.test.js`
- `test-js/scenario-physical.test.js`
- `test-js/scene-layout.test.js`
- `test-js/scene-picking.test.js`
- `test-js/scene-selection.test.js`
- `test-js/scene3d.test.js`
- `test-js/select-routes.test.js`
- `test-js/serve-cache.test.js`
- `test-js/serve.test.js`
- `test-js/sink-inspector.test.js`
- `test-js/sink-paths.test.js`
- `test-js/sink-view.test.js`
- `test-js/step-analysis.test.js`
- `test-js/step-evidence-loader.test.js`
- `test-js/storage-audit.test.js`
- `test-js/storage.test.js`
- `test-js/timing-path-explanation.test.js`
- `test-js/timing-paths.test.js`
- `test-js/timing-report.test.js`
- `test-js/visibility.test.js`
- `test/hls_spacetime_artifact_tests.erl`
- `test/hls_spacetime_import_tests.erl`
- `test/hls_spacetime_memory_fixture.erl`
- `test/hls_spacetime_memory_fixture_tests.erl`
- `test/hls_spacetime_sdf_arcs_tests.erl`
- `test/hls_spacetime_sdf_tests.erl`
- `test/hls_spacetime_tests.erl`
- `test/hls_spacetime_trace_tests.erl`
- `test/memory_witness.escript`
- `test/native/export_route_graph_tests.tcl`
- `test/native/export_routes_tests.tcl`
- `test/native/route_hash_worker_tests.py`
- `test/native/spacetime_trace_tests.cpp`
- `test_data/spacetime_example.term`
- `web/action-chain.js`
- `web/app.js`
- `web/arrival-circuits.js`
- `web/arrival-events.js`
- `web/arrival-layout.js`
- `web/arrival-ruler.js`
- `web/arrival-scene.js`
- `web/camera3d.js`
- `web/candidate-cut.js`
- `web/circuit-display.js`
- `web/clock-reference.js`
- `web/clock-sink.js`
- `web/clocked-host.js`
- `web/clocked-owner.js`
- `web/clocked-resources.js`
- `web/clocked-transport.js`
- `web/computation-loader.js`
- `web/computation-routes.js`
- `web/computation-view.js`
- `web/control-replay.js`
- `web/footprint.js`
- `web/index.html`
- `web/labels.js`
- `web/latency-scenario.js`
- `web/metrics.js`
- `web/model.js`
- `web/native-paths.js`
- `web/native-routes.js`
- `web/neighborhood-scene.js`
- `web/overlay-display.js`
- `web/paint-cache.js`
- `web/path-explorer.js`
- `web/path-neighborhood.js`
- `web/perceptual-color.js`
- `web/prepared-computations.js`
- `web/prepared-format.js`
- `web/prepared-loader.js`
- `web/prepared-worker.js`
- `web/recorded-scenario.js`
- `web/recording-loader.js`
- `web/recording-model.js`
- `web/recording-worker.js`
- `web/regional-controls.js`
- `web/regional-data.js`
- `web/regional-loader.js`
- `web/regional-view.js`
- `web/regional-worker.js`
- `web/scenario-controls.js`
- `web/scenario-physical.js`
- `web/scene-layout.js`
- `web/scene-picking.js`
- `web/scene-selection.js`
- `web/scene3d.js`
- `web/sink-inspector.js`
- `web/sink-paths.js`
- `web/sink-view.js`
- `web/step-analysis.js`
- `web/step-comparison.css`
- `web/step-comparison.js`
- `web/step-evidence-loader.js`
- `web/style.css`
- `web/timing-paths.js`
- `web/timing-report.js`
- `web/visibility.js`
