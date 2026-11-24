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

    /** Return switch tiles for the unique branch from a mapped driver site pin to this sink. */
    static String branch(Design design, String[] pair, Map<Net, Map<Node, PIP>> trees) {
        Cell source = design.getCell(pair[0]), sink = design.getCell(pair[2]);
        if (source == null || sink == null) return "?";
        String sw = source.getSiteWireNameFromLogicalPin(pair[1]);
        String dw = sink.getSiteWireNameFromLogicalPin(pair[3]);
        if (sw == null || dw == null) return "?";
        Net net = source.getSiteInst().getNetFromSiteWire(sw);
        if (net == null || net != sink.getSiteInst().getNetFromSiteWire(dw)) return "?";
        if (source.getSiteInst() == sink.getSiteInst() && sw.equals(dw)) return "=";
        Set<Node> roots = new HashSet<>();
        for (SitePinInst pin : source.getAllSitePinsFromLogicalPin(pair[1], new ArrayList<>()))
            if (pin != null && pin.isOutPin() && pin.getNet() == net) roots.add(pin.getConnectedNode());
        Set<Node> sinks = new HashSet<>();
        for (SitePinInst pin : sink.getAllSitePinsFromLogicalPin(pair[3], new ArrayList<>()))
            if (pin != null && !pin.isOutPin() && pin.getNet() == net) sinks.add(pin.getConnectedNode());
        if (roots.isEmpty() || sinks.size() != 1) return "?";
        Map<Node, PIP> incoming = trees.computeIfAbsent(net, FlowRoutes::parents);
        Node node = sinks.iterator().next();
        Set<Node> visited = new HashSet<>();
        List<String> tiles = new ArrayList<>();
        while (!roots.contains(node)) {
            PIP pip = incoming.get(node);
            if (pip == null || !visited.add(node)) return "?";
            String tile = pip.getTile().getName();
            if (tiles.isEmpty() || !tiles.get(tiles.size()-1).equals(tile)) tiles.add(tile);
            node = pip.isReversed() ? pip.getEndNode() : pip.getStartNode();
        }
        Collections.reverse(tiles);
        return tiles.isEmpty() ? "=" : String.join(" ", tiles);
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
