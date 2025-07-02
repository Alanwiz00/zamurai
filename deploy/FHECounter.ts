import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying FHECounter contract with account:", deployer.address);

  const FHECounter = await ethers.getContractFactory("FHECounter");
  const counter = await FHECounter.deploy();

  await counter.waitForDeployment();

  console.log("FHECounter deployed to:", await counter.getAddress());
  console.log("Transaction hash:", counter.deploymentTransaction()?.hash);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
