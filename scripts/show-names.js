const hre = require("hardhat");
const data = require("../addresses_542000.json");

async function main() {
  //   console.table(data.addresses);

  // display all addresses with wordStart == "c0de" or wordEnd == "c0de"
  const word = "3333";
  const filtered = data.addresses.filter((address) => {
    return address.wordStart === word || address.wordEnd === word;
  });
  console.table(filtered);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
