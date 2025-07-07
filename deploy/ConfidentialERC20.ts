import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying ConfidentialERC20 contract with account:", deployer.address);

  const ConfidentialERC20 = await ethers.getContractFactory("ConfidentialERC20");
  const ConfidentialERC20Contract = await ConfidentialERC20.deploy({
    gasLimit: 500000, // Adjust gas limit as needed
  });

  await ConfidentialERC20Contract.waitForDeployment();

  console.log("ConfidentialERC20 deployed to:", await ConfidentialERC20Contract.getAddress());
  console.log("Transaction hash:", ConfidentialERC20Contract.deploymentTransaction()?.hash);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
