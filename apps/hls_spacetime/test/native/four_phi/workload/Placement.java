import com.xilinx.rapidwright.design.Cell;
import com.xilinx.rapidwright.design.Design;
import java.io.BufferedWriter;
import java.nio.file.Files;
import java.nio.file.Path;

/** Export DCP cell, primitive type, site and BEL with a separately supplied readable logical view. */
class Placement {
    /** Read the archived XDEF and matching EDIF without invoking Vivado or running implementation. */
    public static void main(String[] args) throws Exception {
        Design.setAutoGenerateReadableEdif(false);
        Design.setReadEdifAndXdefInParallel(false);
        Design design = Design.readCheckpoint(args[0], args[2]);
        try (BufferedWriter out = Files.newBufferedWriter(Path.of(args[1]))) {
            for (Cell cell : design.getCells()) {
                out.write(String.join("\t", cell.getName(), cell.getType(),
                    String.valueOf(cell.getSiteName()), String.valueOf(cell.getBELName())));
                out.newLine();
            }
        }
    }
}
