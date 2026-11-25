"""Read placement and used-wire membership from nextpnr-xilinx's prjxray v1 BBA layout."""
import mmap
import struct


class ChipGrid:
    """Index tile and site owners. Keep the caller's read-only database mapping open during use."""

    def __init__(self, db: mmap.mmap) -> None:
        """Validate the supported header and index native tile and site names."""
        self.db = db
        header = self.pointer(0)
        self.part = self.name(header)
        self.width, height, self.count = struct.unpack_from("<iii", db, header + 12)
        if (self.name(header + 4) != "prjxray" or self.word(header + 8) != 1 or
                min(self.width, height) < 1 or self.count != self.width * height or
                self.count > 2_000_000):
            raise ValueError("unsupported chipdb header")
        self.tiles = self.pointer(header + 36)
        self.types = self.pointer(header + 32)
        self.type_count = self.word(header + 24)
        self.nodes = self.pointer(header + 40)
        self.node_count = self.word(header + 28)
        self.owners = {}
        self.tile_names = []
        for index in range(self.count):
            tile = self.tiles + index * 24
            tile_name = self.name(tile)
            self.tile_names.append(tile_name)
            site_count = self.word(tile + 16)
            if not 0 <= site_count <= 4096:
                raise ValueError("invalid chipdb site count")
            sites = self.pointer(tile + 20) if site_count else 0
            for owner in [tile_name] + [self.name(sites + i * 32) for i in range(site_count)]:
                if owner in self.owners:
                    raise ValueError(f"ambiguous chipdb location {owner}")
                self.owners[owner] = index

    def word(self, at: int) -> int:
        """Read one signed little-endian field after checking its extent."""
        if not 0 <= at <= len(self.db) - 4:
            raise ValueError("chipdb field outside file")
        return struct.unpack_from("<i", self.db, at)[0]

    def pointer(self, at: int) -> int:
        """BBA offset32 references count four-byte words from the reference field."""
        dest = at + 4 * self.word(at)
        if not 0 <= dest < len(self.db):
            raise ValueError("chipdb reference outside file")
        return dest

    def name(self, at: int) -> str:
        """Decode one terminated chipdb name at a relative string reference."""
        start = self.pointer(at)
        end = self.db.find(b"\0", start, start + 4096)
        if end == -1:
            raise ValueError("unterminated chipdb name")
        return self.db[start:end].decode("ascii")

    def location(self, owner: str) -> dict:
        """Return the owning grid tile and distinguish its native site, if present."""
        index = self.owners[owner]
        tile = self.tile_names[index]
        return {"tile": tile, "site": None if tile == owner else owner,
                "x": index % self.width, "y": index // self.width}

    def wire_key(self, owner: str, index: int) -> tuple[int, int]:
        """Canonicalize a tile-local wire exactly as nextpnr's canonicalWireId does."""
        tile_id = self.owners[owner]
        tile = self.tiles + tile_id * 24
        tile_type = self.word(tile + 4)
        if not 0 <= tile_type < self.type_count:
            raise ValueError("invalid tile type")
        if not 0 <= index < self.word(self.types + tile_type * 32 + 12):
            raise ValueError("wire index outside tile type")
        if index < self.word(tile + 8):
            node = self.word(self.pointer(tile + 12) + index * 4)
            if node != -1:
                if not 0 <= node < self.node_count:
                    raise ValueError("wire node outside database")
                return -1, node
        return tile_id, index

    def wires(self, key: tuple[int, int], remaining: int) -> list[dict]:
        """Return the actual constituent tile wires of a native routing node within the budget."""
        tile_id, index = key
        if tile_id == -1:
            node = self.nodes + index * 12
            count = self.word(node)
            if not 0 < count <= remaining:
                raise ValueError("wire footprint exceeds route object limit")
            start = self.pointer(node + 8)
            members = (struct.unpack_from("<ii", self.db, start + 8 * i) for i in range(count))
        else:
            members = [key]
        rows = []
        for tile, wire in members:
            if not 0 <= tile < self.count or self.wire_key(self.tile_names[tile], wire) != key:
                raise ValueError("inconsistent native node membership")
            name = self.tile_names[tile]
            rows.append({"id": f"{name}/{wire}", "tile": name,
                         "x": tile % self.width, "y": tile // self.width})
        return rows
