import com.xilinx.rapidwright.design.*;
import com.xilinx.rapidwright.device.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;

/** Join exact logical pin pairs to used, directed checkpoint PIPs, in source-to-sink order. */
class FlowRoutes {
    /** Index one net's incoming used switches. Ambiguous predecessors cannot certify a branch. */
    static Map<Node, PIP> parents(Net net) {
        Map<Node, PIP> result = new HashMap<>();
        for (PIP pip : net.getPIPs()) {
            Node end = pip.isReversed() ? pip.getStartNode() : pip.getEndNode();
            result.put(end, result.containsKey(end) ? null : pip);
        }
        return result;
    }

    /** Follow the used PIPs back to a certified output, rejecting cycles and missing parents. */
    record FabricPath(Node root, List<PIP> pips) {
        static FabricPath trace(Set<Node> roots, Node end, Map<Node, PIP> incoming) {
            if (roots.isEmpty()) return null;
            Set<Node> visited = new HashSet<>();
            List<PIP> path = new ArrayList<>();
            while (!roots.contains(end)) {
                PIP pip = incoming.get(end);
                if (pip == null || !visited.add(end)) return null;
                path.add(pip);
                end = pip.isReversed() ? pip.getEndNode() : pip.getStartNode();
            }
            Collections.reverse(path);
            return new FabricPath(end, path);
        }

        /** Consecutive PIPs in one tile occupy one point at gallery resolution. */
        String tiles() {
            List<String> tiles = new ArrayList<>();
            for (PIP pip : pips) {
                String tile = pip.getTile().getName();
                if (tiles.isEmpty() || !tiles.getLast().equals(tile)) tiles.add(tile);
            }
            return tiles.isEmpty() ? "=" : String.join(" ", tiles);
        }
    }

    /** Bind an additional exit only through a used mux and a checkpoint FF route-through on this net. */
    static Map<Node, String> ffExits(Cell source, String wire, Net net) {
        Map<Node, String> exits = new HashMap<>();
        SiteInst site = source.getSiteInst();
        for (SitePIP pip : site.getUsedSitePIPs()) {
            if (!wire.equals(pip.getInputPin().getSiteWireName())) continue;
            String input = pip.getOutputPin().getSiteWireName();
            if (site.getNetFromSiteWire(input) != net) continue;
            for (Cell ff : site.getCells()) {
                if (!ff.isFFRoutethruCell() || !ff.isRoutethru() ||
                    !input.equals(ff.getSiteWireNameFromLogicalPin("D"))) continue;
                String q = ff.getSiteWireNameFromLogicalPin("Q");
                if (q == null || site.getNetFromSiteWire(q) != net) continue;
                for (SitePinInst pin : site.getSitePinInsts()) {
                    if (pin.isOutPin() && pin.getNet() == net && q.equals(pin.getSiteWireName())) {
                        Node node = pin.getConnectedNode();
                        String via = site.getSiteName() + "/" + pip + " → " + ff.getBELName() + " D→Q";
                        if (node != null) exits.put(node, exits.containsKey(node) ? null : via);
                    }
                }
            }
        }
        exits.values().removeIf(Objects::isNull);
        return exits;
    }

    /** Match each mapped sink wire to its distinct site terminal, optionally through one selected mux. */
    static Map<SitePinInst, String> sinkEntries(Cell sink, Net net, Set<String> mapped, Set<SitePinInst> pins) {
        SiteInst site = sink.getSiteInst();
        Map<SitePinInst, String> entries = new HashMap<>();
        if (mapped == null || mapped.size() != pins.size()) return null;
        for (String physical : mapped) {
            String wire = sink.getSiteWireNameFromPhysicalPin(physical);
            if (wire == null || site.getNetFromSiteWire(wire) != net) return null;
            int matches = 0;
            for (SitePinInst pin : pins) {
                String entry = pin.getSiteWireName();
                if (site.getNetFromSiteWire(entry) != net) continue;
                if (wire.equals(entry)) {
                    if (entries.put(pin, "") != null) return null;
                    matches++;
                } else {
                    for (SitePIP mux : site.getUsedSitePIPs()) {
                        if (entry.equals(mux.getInputPin().getSiteWireName()) &&
                            wire.equals(mux.getOutputPin().getSiteWireName())) {
                            if (entries.put(pin, site.getSiteName() + "/" + mux) != null) return null;
                            matches++;
                        }
                    }
                }
            }
            if (matches != 1) return null;
        }
        return entries;
    }

    /** Trace every mapped physical sink of one logical pin, preserving a single SDF connection. */
    static String fabric(Cell source, String sw, Cell sink, String[] pair, Net net,
                         Map<Net, Map<Node, PIP>> trees, Set<String> mapped) {
        Set<Node> roots = new HashSet<>();
        for (SitePinInst pin : source.getAllSitePinsFromLogicalPin(pair[1], new ArrayList<>()))
            if (pin != null && pin.isOutPin() && pin.getNet() == net && pin.getConnectedNode() != null)
                roots.add(pin.getConnectedNode());
        List<SitePinInst> sinks = sink.getAllSitePinsFromLogicalPin(pair[3], new ArrayList<>());
        if (sinks.isEmpty() || sinks.stream().anyMatch(pin -> pin == null || pin.isOutPin() ||
            pin.getNet() != net || pin.getConnectedNode() == null)) return "?";
        Set<SitePinInst> terminals = new HashSet<>(sinks);
        Map<SitePinInst, String> entries = Collections.emptyMap();
        if (terminals.size() > 1 || (mapped != null && mapped.size() > 1)) {
            entries = sinkEntries(sink, net, mapped, terminals);
            if (entries == null) return "?";
        }
        Map<Node, PIP> incoming = trees.computeIfAbsent(net, FlowRoutes::parents);
        Map<Node, String> exits = null;
        List<String> parts = new ArrayList<>();
        for (SitePinInst pin : terminals.stream().sorted(Comparator.comparing(SitePinInst::getName)).toList()) {
            FabricPath path = FabricPath.trace(roots, pin.getConnectedNode(), incoming);
            String via = "";
            if (path == null) {
                if (exits == null) exits = ffExits(source, sw, net);
                path = FabricPath.trace(exits.keySet(), pin.getConnectedNode(), incoming);
                if (path == null) return "?";
                via = exits.get(path.root());
            }
            if (terminals.size() == 1 && via.isEmpty()) return path.tiles();
            parts.add(sink.getSiteName() + "/" + pin.getName());
            String entry = entries.getOrDefault(pin, "");
            parts.add(via.isEmpty() ? entry : entry.isEmpty() ? via : via + " → " + entry);
            parts.add(path.tiles());
        }
        return "+" + String.join("\t", parts);
    }

    /** Return switch tiles for the unique branch from a mapped driver site pin to this sink. */
    static String branch(Design design, String[] pair, Map<Net, Map<Node, PIP>> trees) {
        Cell source = design.getCell(pair[0]), sink = design.getCell(pair[2]);
        if (source == null || sink == null) return "?";
        String sw = source.getSiteWireNameFromLogicalPin(pair[1]);
        String dw = sink.getSiteWireNameFromLogicalPin(pair[3]);
        if (sw == null || dw == null) return "?";
        Net net = source.getSiteInst().getNetFromSiteWire(sw);
        if (net == null || net != sink.getSiteInst().getNetFromSiteWire(dw)) return "?";
        Set<String> mapped = sink.getAllPhysicalPinMappings(pair[3]);
        if (source.getSiteInst() == sink.getSiteInst() && (mapped == null || mapped.size() <= 1)) {
            if (sw.equals(dw)) return "=";
            SitePIP selected = null;
            for (SitePIP pip : source.getSiteInst().getUsedSitePIPs()) {
                if (!sw.equals(pip.getInputPin().getSiteWireName()) ||
                    !dw.equals(pip.getOutputPin().getSiteWireName())) continue;
                if (selected != null) return "?";
                selected = pip;
            }
            if (selected != null) return "@" + selected;
        }
        return fabric(source, sw, sink, pair, net, trees, mapped);
    }

    /** Stream one result per requested pair; retain only the current driver's routing tree. */
    public static void main(String[] args) throws Exception {
        Design.setAutoGenerateReadableEdif(false);
        Design.setReadEdifAndXdefInParallel(false);
        Design design = Design.readCheckpoint(args[0], args[1]);
        Map<Net, Map<Node, PIP>> trees = new HashMap<>();
        try (var in = Files.newBufferedReader(Path.of(args[2]));
             var out = Files.newBufferedWriter(Path.of(args[3]))) {
            String line, previous = "";
            while ((line = in.readLine()) != null) {
                String[] pair = line.split("\t", -1);
                if (!previous.equals(pair[0])) trees.clear();
                previous = pair[0];
                out.write(branch(design, pair, trees));
                out.newLine();
            }
        }
    }
}
