import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
import fs from "fs";

const values = [
    ["0xc0de8eff2b9e2b8d38d6db71ab6000c6546647bc", "18000000000000000000"],
    ["0xc0def054dc13c05ddc5fbcff2038924280875827", "18000000000000000000"],
    ["0xc0de248619287170d4549392d11686206127089b", "18000000000000000000"],
    ["0xc0dE521BD4015A537496036276Abd2083082a736", "18000000000000000000"],
    ["0xC0de5B5cDB7828088A2E48390a38e719E1f1bfed", "18000000000000000000"]
  ];

async function SetMerkleRoot(val) {
    const tree = StandardMerkleTree.of(val, ["address", "uint256"]);
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
        for(let i = 0; i < values.length; i++) {
            const addr = values[i][0];
            ObtainingProof(addr);
        }
    
}

main().then(async () => {
    console.log("===================");
});