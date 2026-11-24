// Optional observer for the pinned nextpnr-xilinx backend. All delays use its native ps unit.
// Included by xilinx/main.cc after json11.hpp and USING_NEXTPNR_NAMESPACE.
namespace {
using json11::Json;

// Account for queries as well as serialized rows, including absent arcs.
void chargeSpacetime(int &remaining)
{
    if (remaining-- <= 0)
        log_error("Spacetime observer object limit exceeded\n");
}

// Keep pre-pack instance and connected net identities on the objects the packer transforms.
void markSpacetimeOrigins(Context *ctx, int limit)
{
    for (auto &item : ctx->nets) {
        chargeSpacetime(limit);
        auto &net = *item.second;
        if (net.attrs.count(ctx->id("SPACETIME_NET")))
            log_error("Reserved SPACETIME_NET attribute on synthesis net\n");
        net.attrs[ctx->id("SPACETIME_NET")] = net.name.str(ctx);
    }
    for (auto &item : ctx->cells) {
        chargeSpacetime(limit);
        auto &cell = *item.second;
        for (const auto &attr : cell.attrs)
            if (attr.first.str(ctx).find("SPACETIME_") == 0)
                log_error("Reserved SPACETIME_ attribute on synthesis cell\n");
        cell.attrs[ctx->id("SPACETIME_CELL")] = cell.name.str(ctx);
        for (const auto &entry : cell.ports) {
            chargeSpacetime(limit);
            if (entry.second.net != nullptr)
                cell.attrs[ctx->id("SPACETIME_PORT_" + entry.first.str(ctx))] = entry.second.net->name.str(ctx);
        }
    }
}

// Query the same cell and sink delay APIs used by the timing walk, retaining unknown answers.
void writeSpacetimeTiming(Context *ctx, const std::string &filename, int limit, const std::string &route_request)
{
    const int maximum = limit;
    int route_work = 32 * limit;
    static const char *classes[] = {"clock_input", "generated_clock", "register_input", "register_output",
                                   "comb_input", "comb_output", "startpoint", "endpoint", "ignore"};
    Json::object cells;
    Json::array sinks;
    Json::object selected;
    if (!route_request.empty()) {
        std::ifstream in(route_request);
        std::string data((std::istreambuf_iterator<char>(in)), {}), error;
        auto request = Json::parse(data, error);
        if (!error.empty() || !request["nets"].is_array())
            log_error("Invalid Spacetime route request\n");
        for (const auto &alias : request["nets"].array_items()) {
            auto net = ctx->getNetByAlias(ctx->id(alias.string_value()));
            if (net == nullptr)
                log_error("Unknown selected net '%s'\n", alias.string_value().c_str());
            selected[net->name.str(ctx)] = Json();
        }
    }
    for (const auto &item : ctx->cells) {
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
        cells[cell->name.str(ctx)] = Json::object{{"type", cell->type.str(ctx)}, {"ports", ports}, {"arcs", arcs}};
    }
    for (const auto &item : ctx->nets) {
        const NetInfo *net = item.second.get();
        auto driver = net->driver;
        if (selected.count(net->name.str(ctx))) {
            Json::array pins, aliases;
            Json::object wires;
            for (auto &al : ctx->net_aliases)
                if (al.second == net->name) {
                    chargeSpacetime(limit);
                    aliases.push_back(al.first.str(ctx));
                }
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
            selected[net->name.str(ctx)] = Json::object{{"aliases", aliases}, {"wires", wires}, {"pins", pins}};
        }
        for (const auto &user : net->users) {
            chargeSpacetime(limit);
            auto src = ctx->getNetinfoSourceWire(net);
            auto dst = ctx->getNetinfoSinkWire(net, user);
            bool endpoints = src != WireId() && dst != WireId() && driver.cell != nullptr;
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
    std::ofstream out(filename);
    out << Json(Json::object{{"schema", 1}, {"unit", "ps"}, {"objects", maximum - limit},
                            {"cells", cells}, {"sinks", sinks}, {"selected_routes", selected}}).dump() << '\n';
    out.close();
    if (!out)
        log_error("Cannot write complete Spacetime timing export\n");
}
} // namespace
