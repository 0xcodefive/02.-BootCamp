import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
import fs from "fs";

const values = [
    ["0x1111111111111111111111111111111111111111"],
    ["0x2222222222222222222222222222222222222222"]
  ];

async function SetMerkleRoot(val) {
    const tree = StandardMerkleTree.of(val, ["address"]);
    console.log('Merkle Root:', tree.root);
    fs.writeFileSync("tree.json", JSON.stringify(tree.dump()));
}

async function ObtainingProof(addr) {
    const tree = StandardMerkleTree.load(JSON.parse(fs.readFileSync("tree.json")));
    for (const [i, v] of tree.entries()) {
        if (v[0] === addr) {
            const proof = tree.getProof(i);
            console.log('Value:', v);
            console.log('Proof:', proof);
            return
        }
    }
    console.log(`Address: ${addr} it not valid`);
}

async function main() {
    SetMerkleRoot(values);
    const addr = values[0][0];
    ObtainingProof(addr);
}

main().then(async () => {
    console.log("===================");
});