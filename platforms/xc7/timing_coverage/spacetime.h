// Optional observer for the pinned nextpnr-xilinx backend. All delays use its native ps unit.
// Included by xilinx/main.cc after json11.hpp and USING_NEXTPNR_NAMESPACE.
NEXTPNR_NAMESPACE_BEGIN
void writeSpacetimeSta(Context *ctx, const std::string &file, int limit, int endpoints);
NEXTPNR_NAMESPACE_END

namespace {
using json11::Json;

// Stream the incremental ps on each bound wire, including its incoming switch.
// A sink-specific path can then be reconciled independently with the SDF.
void writeSpacetimeWireDelays(Context *ctx, const std::string &filename)
{
    std::ofstream out(filename);
    for (const auto &entry : ctx->nets) {
        const auto *net = entry.second.get();
        for (const auto &binding : net->wires) {
            auto wire = binding.first;
            auto pip = binding.second.pip;
            auto delay = ctx->getWireDelay(wire).maxDelay();
            if (pip != PipId())
                delay += ctx->getPipDelay(pip).maxDelay();
            out << "W\t" << net->name.str(ctx) << '\t' << ctx->getWireName(wire).str(ctx) << '\t' << delay << '\n';
        }
    }
    out.close();
    if (!out)
        log_error("Cannot write complete Spacetime wire delays\n");
}

// Account for queries as well as serialized rows, including absent arcs.
void chargeSpacetime(int &remaining)
{
    if (remaining-- <= 0)
        log_error("Spacetime observer object limit exceeded\n");
}

// A focused export starts at exact synthesis FF instances. Only a nominated root crosses
// a register boundary backwards; the clock tree and unqualified hard blocks stop traversal.
using SpacetimeCells = std::set<IdString>;

SpacetimeCells readSpacetimeRoots(Context *ctx, const std::string &file, int limit)
{
    std::ifstream in(file);
    std::string data((std::istreambuf_iterator<char>(in)), {}), error;
    auto json = Json::parse(data, error);
    if (!error.empty() || !json.is_array() || json.array_items().empty() || int(json.array_items().size()) > limit)
        log_error("Invalid Spacetime root list\n");
    SpacetimeCells roots;
    for (const auto &name : json.array_items()) {
        auto id = ctx->id(name.string_value());
        if (!name.is_string() || !ctx->cells.count(id) || ctx->cells.at(id)->type != ctx->id("FDRE") ||
            !roots.insert(id).second)
            log_error("Invalid or duplicate Spacetime FDRE root '%s'\n", name.string_value().c_str());
    }
    return roots;
}

// Retain each reachable cell once, bounding fan-in traversal independently of output serialization.
SpacetimeCells spacetimeFanin(Context *ctx, const SpacetimeCells &roots, int limit)
{
    SpacetimeCells found = roots;
    std::vector<IdString> queue(roots.begin(), roots.end());
    while (!queue.empty()) {
        auto name = queue.back();
        queue.pop_back();
        if (!ctx->cells.count(name))
            log_error("Spacetime root absent after packing: %s\n", name.c_str(ctx));
        const auto &cell = *ctx->cells.at(name);
        const auto type = cell.type.str(ctx);
        if (roots.count(name)) {
            if (type != "FDRE" && type != "SLICE_FFX")
                log_error("Spacetime root is no longer a register\n");
        } else if (type != "CARRY4" && type != "INV" && type != "MUXF7" && type != "MUXF8" &&
                   type != "SELMUX2_1" && type.compare(0, 3, "LUT") != 0 && type != "SLICE_LUTX") {
            continue;
        }
        if (cell.attrs.count(ctx->id("X_LUT_AS_SRL")) || cell.attrs.count(ctx->id("X_LUT_AS_DRAM")))
            continue;
        for (const auto &entry : cell.ports) {
            chargeSpacetime(limit);
            const auto &p = entry.second;
            if (p.type != PORT_IN || !p.net || !p.net->driver.cell || p.name == ctx->id("C") ||
                p.name == ctx->id("CK"))
                continue;
            auto src = p.net->driver.cell->name;
            if (found.insert(src).second)
                queue.push_back(src);
        }
    }
    return found;
}

// Keep pre-pack instance and connected net identities on the objects the packer transforms.
void markSpacetimeOrigins(Context *ctx, int limit, const SpacetimeCells &roots)
{
    auto cells = spacetimeFanin(ctx, roots, limit);
    SpacetimeCells nets;
    for (auto id : cells)
        for (const auto &p : ctx->cells.at(id)->ports)
            if (p.second.net) nets.insert(p.second.net->name);
    for (auto &item : ctx->nets) {
        auto &net = *item.second;
        if (net.attrs.count(ctx->id("SPACETIME_NET")))
            log_error("Reserved SPACETIME_NET attribute on synthesis net\n");
        if (roots.empty() || nets.count(net.name)) {
            chargeSpacetime(limit);
            net.attrs[ctx->id("SPACETIME_NET")] = net.name.str(ctx);
        }
    }
    for (auto &item : ctx->cells) {
        auto &cell = *item.second;
        for (const auto &attr : cell.attrs)
            if (attr.first.str(ctx).find("SPACETIME_") == 0)
                log_error("Reserved SPACETIME_ attribute on synthesis cell\n");
        if (!roots.empty() && !cells.count(cell.name)) continue;
        chargeSpacetime(limit);
        cell.attrs[ctx->id("SPACETIME_CELL")] = cell.name.str(ctx);
        for (const auto &entry : cell.ports) {
            chargeSpacetime(limit);
            if (entry.second.net != nullptr)
                cell.attrs[ctx->id("SPACETIME_PORT_" + entry.first.str(ctx))] = entry.second.net->name.str(ctx);
        }
    }
}

// Query the same cell and sink delay APIs used by the timing walk, retaining unknown answers.
void writeSpacetimeTiming(Context *ctx, const std::string &filename, int limit, const std::string &route_request,
                          const SpacetimeCells &roots, const std::string &sta_file, const Json::object &lut_buffers)
{
    const int maximum = limit;
    int route_work = 32 * limit;
    static const char *classes[] = {"clock_input", "generated_clock", "register_input", "register_output",
                                   "comb_input", "comb_output", "startpoint", "endpoint", "ignore"};
    Json::object cells;
    Json::array sinks;
    Json::object selected;
    const auto focus = spacetimeFanin(ctx, roots, limit);
    bool all_routes = false;
    std::map<IdString, Json::array> route_aliases;
    if (!route_request.empty()) {
        std::ifstream in(route_request);
        std::string data((std::istreambuf_iterator<char>(in)), {}), error;
        auto request = Json::parse(data, error);
        if (!error.empty() || !request["nets"].is_array())
            log_error("Invalid Spacetime route request\n");
        all_routes = request["all"].bool_value();
        if (request["sta_nets"].bool_value()) {
            if (sta_file.empty()) log_error("STA net selection needs a post-route STA report\n");
            std::ifstream sta(sta_file);
            std::string raw((std::istreambuf_iterator<char>(sta)), {});
            auto report = Json::parse(raw, error);
            if (!error.empty() || !report["paths"].is_array()) log_error("Invalid Spacetime STA report\n");
            for (const char *group : {"paths", "ranked_endpoints"})
                for (const auto &path : report[group].array_items())
                    for (const auto &point : path["points"].array_items())
                        if (point["kind"].string_value() == "net")
                            selected[point["net"].string_value()] = Json();
        }
        for (const auto &root : request["data_roots"].array_items()) {
            IdString name = ctx->id(root.string_value());
            if (!roots.count(name)) log_error("Route data root outside timing scope\n");
            const auto &port = ctx->cells.at(name)->ports.at(ctx->id("D"));
            if (!port.net) log_error("Unconnected data route root\n");
            selected[port.net->name.str(ctx)] = Json();
        }
        if (request["root_data"].bool_value()) {
            if (roots.empty()) log_error("Root-data routing needs a root list\n");
            for (auto id : roots) {
                const auto &d = ctx->cells.at(id)->ports.at(ctx->id("D"));
                if (d.net) selected[d.net->name.str(ctx)] = Json();
            }
        }
        for (const auto &alias : request["nets"].array_items()) {
            auto net = ctx->getNetByAlias(ctx->id(alias.string_value()));
            if (net == nullptr)
                log_error("Unknown selected net '%s'\n", alias.string_value().c_str());
            selected[net->name.str(ctx)] = Json();
        }
        for (const auto &al : ctx->net_aliases)
            if (all_routes ? ctx->nets.count(al.second) : selected.count(al.second.str(ctx))) {
                chargeSpacetime(limit);
                route_aliases[al.second].push_back(al.first.str(ctx));
            }
    }
    for (const auto &item : ctx->cells) {
        if (!roots.empty() && !focus.count(item.first)) continue;
        chargeSpacetime(limit);
        const CellInfo *cell = item.second.get();
        Json::object ports;
        Json::array arcs;
        for (const auto &entry : cell->ports) {
            const auto &port = entry.second;
            if (port.net == nullptr)
                continue;
            chargeSpacetime(limit);
            int count = 0;
            auto kind = ctx->getPortTimingClass(cell, port.name, count);
            Json::array clocks;
            for (int i = 0; i < count; ++i) {
                chargeSpacetime(limit);
                auto info = ctx->getPortClockingInfo(cell, port.name, i);
                Json::object clock{{"port", info.clock_port.str(ctx)}, {"edge", info.edge == RISING_EDGE ? "rising" : "falling"}};
                if (kind == TMG_REGISTER_INPUT) {
                    clock["setup_ps"] = info.setup.maxDelay();
                    clock["hold_ps"] = info.hold.maxDelay();
                } else if (kind == TMG_REGISTER_OUTPUT) {
                    clock["clock_to_q_ps"] = info.clockToQ.maxDelay();
                }
                clocks.push_back(clock);
            }
            IdString bel_pin = cell->pins.count(port.name) ? cell->pins.at(port.name) : port.name;
            WireId wire = cell->bel == BelId() ? WireId() : ctx->getBelPinWire(cell->bel, bel_pin);
            const auto &attrs = port.net->attrs;
            ports[port.name.str(ctx)] = Json::object{
                {"class", classes[int(kind)]}, {"clocks", clocks}, {"net", port.net->name.str(ctx)},
                {"net_origin", attrs.count(ctx->id("SPACETIME_NET")) ? Json(attrs.at(ctx->id("SPACETIME_NET")).str) : Json()},
                {"bel_pin", bel_pin.str(ctx)}, {"wire", wire == WireId() ? Json() : Json(ctx->getWireName(wire).str(ctx))},
                {"bound", wire != WireId() && port.net->wires.count(wire) != 0},
                {"direction", port.type == PORT_OUT ? "OUT" : port.type == PORT_IN ? "IN" : "INOUT"}};
            if (kind != TMG_COMB_INPUT)
                continue;
            for (const auto &out : cell->ports) {
                if (out.second.type != PORT_OUT || out.second.net == nullptr)
                    continue;
                chargeSpacetime(limit);
                DelayInfo delay;
                bool valid = ctx->getCellDelay(cell, port.name, out.first, delay);
                std::string model = "architecture";
                if (cell->type == ctx->id("SLICE_LUTX"))
                    model = cell->bel != BelId() && ctx->locInfo(cell->bel).bel_data[cell->bel.index].timing_inst != -1
                                ? "chipdb_cell_table" : "compiled_LUT_fallback";
                arcs.push_back(Json::object{{"from", port.name.str(ctx)}, {"to", out.first.str(ctx)},
                    {"model", model}, {"delay_ps", valid ? Json(delay.maxDelay()) : Json()}});
            }
        }
        Json::object row{{"type", cell->type.str(ctx)}, {"ports", ports}, {"arcs", arcs}};
        auto buffer = lut_buffers.find(cell->name.str(ctx));
        if (buffer != lut_buffers.end()) {
            chargeSpacetime(limit);
            row.emplace("lut_buffer", buffer->second);
        }
        cells[cell->name.str(ctx)] = std::move(row);
    }
    for (const auto &item : ctx->nets) {
        const NetInfo *net = item.second.get();
        auto driver = net->driver;
        if (all_routes || selected.count(net->name.str(ctx))) {
            Json::array pins;
            Json::object wires;
            auto record_pin = [&](const PortRef &ref, const char *direction) {
                chargeSpacetime(limit);
                auto ci = ref.cell;
                IdString port = ref.port;
                IdString bp = ci && ci->pins.count(port) ? ci->pins.at(port) : port;
                auto bel = ci ? ci->bel : BelId();
                auto wire = bel != BelId() ? ctx->getBelPinWire(bel, bp) : WireId();
                pins.push_back(Json::object{{"cell", ci ? Json(ci->name.str(ctx)) : Json()},
                    {"port", port.str(ctx)}, {"direction", direction},
                    {"bel", bel != BelId() ? Json(ctx->getBelName(bel).str(ctx)) : Json()},
                    {"bel_pin", bel != BelId() ? Json(bp.str(ctx)) : Json()},
                    {"wire", wire != WireId() ? Json(ctx->getWireName(wire).str(ctx)) : Json()}});
            };
            record_pin(driver, "OUT");
            for (const auto &user : net->users)
                record_pin(user, "IN");
            for (const auto &binding : net->wires) {
                chargeSpacetime(limit);
                auto wire = binding.first;
                int local = wire.tile == -1 ? ctx->chip_info->nodes[wire.index].tile_wires[0].index : wire.index;
                auto pip = binding.second.pip;
                wires[ctx->getWireName(wire).str(ctx)] = Json::object{{"index", local},
                    {"incoming", pip == PipId() ? Json() : Json(ctx->getPipName(pip).str(ctx))}};
            }
            selected[net->name.str(ctx)] = Json::object{{"aliases", route_aliases[net->name]}, {"wires", wires}, {"pins", pins}};
        }
        for (const auto &user : net->users) {
            if (!roots.empty() && (!focus.count(user.cell->name) || (driver.cell && !focus.count(driver.cell->name))))
                continue;
            chargeSpacetime(limit);
            auto src = ctx->getNetinfoSourceWire(net);
            auto dst = ctx->getNetinfoTimingSinkWire(net, user);
            bool endpoints = src != WireId() && ctx->getNetinfoSinkWire(net, user) != WireId() && driver.cell != nullptr;
            auto cursor = dst;
            while (endpoints && cursor != src && net->wires.count(cursor)) {
                chargeSpacetime(route_work);
                auto pip = net->wires.at(cursor).pip;
                if (pip == PipId())
                    break;
                cursor = ctx->getPipSrcWire(pip);
            }
            sinks.push_back(Json::object{{"net", net->name.str(ctx)},
                {"source", driver.cell ? Json(driver.cell->name.str(ctx)) : Json()}, {"output", driver.port.str(ctx)},
                {"sink", user.cell->name.str(ctx)}, {"input", user.port.str(ctx)},
                {"model", !endpoints ? "unavailable" : cursor == src && !net->wires.empty() ? "routed" : "predicted"},
                {"delay_ps", endpoints ? Json(ctx->getNetinfoRouteDelay(net, user)) : Json()}});
        }
    }
    Json::array ordered_roots;
    for (auto root : roots) ordered_roots.push_back(root.str(ctx));
    std::ofstream out(filename);
    out << Json(Json::object{{"schema", 1}, {"unit", "ps"}, {"objects", maximum - limit},
                            {"roots", ordered_roots}, {"cells", cells}, {"sinks", sinks}, {"selected_routes", selected}}).dump() << '\n';
    out.close();
    if (!out)
        log_error("Cannot write complete Spacetime timing export\n");
}
} // namespace
