const startUri = 'https://ipfs.io/ipfs/QmeQRCYrquKGz3RNjX2gSqJaK4QZyi3MFpMcTR2TmmgtPt/';

async function getAttributesFromURI(uri) {
    const response = await fetch(uri);
    const json = await response.json();
    
    const attributes = {};
    attributes.name = json.name;
    attributes.description = json.description;
    attributes.image = json.image;
    attributes.backgroundColor = json.background_color;
  
    const traits = {};
    for (const trait of json.attributes) {
      traits[trait.trait_type] = trait.value;
    }
    attributes.traits = traits;
  
    return attributes;
}

async function getAttributesArray(){
    const attributesArray = [];
    for(let i = 0; i < 15; i++){
        let uri = `${startUri}${i}.json`;
        let attribute = await getAttributesFromURI(uri);
        attributesArray.push(attribute);
    }
    return attributesArray;
}