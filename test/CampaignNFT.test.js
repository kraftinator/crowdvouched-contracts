const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CampaignNFT", function () {
    let campaign, campaignNFT, owner, addr1;
    const mintFee = ethers.parseEther("0.01"); // Example mint fee
    const baseURI = "https://arweave.net/"; // Example base URI

    beforeEach(async function () {
      // Get signers
      [owner, addr1] = await ethers.getSigners();
  
      // Deploy Campaign contract
      const Campaign = await ethers.getContractFactory("Campaign");
      campaign = await Campaign.deploy(
          "Test Campaign",
          "Testing the Campaign contract",
          "USC1850",
          "USC",
          baseURI,
          "USC1850 NFT",
          "USCNFT",
          mintFee
      );
  
      // Wait for the Campaign deployment to complete
      await campaign.deployTransaction?.wait(); // Using optional chaining for robustness
  
      // Get the deployed CampaignNFT contract
      const campaignNFTAddress = await campaign.campaignNFT();
      campaignNFT = await ethers.getContractAt("CampaignNFT", campaignNFTAddress);
  });
  

    it("Should mint an NFT for a validated record", async function () {
        const recordId = 1; // Example record ID
        const mintTx = await campaignNFT.connect(addr1).mintRecord(recordId, {
            value: mintFee,
        });

        const receipt = await mintTx.wait();
        expect(receipt.status).to.equal(1);

        // Check ownership
        const ownerOfToken = await campaignNFT.ownerOf(recordId);
        expect(ownerOfToken).to.equal(addr1.address);

        // Verify token URI
        const tokenURI = await campaignNFT.tokenURI(recordId);
        expect(tokenURI).to.equal(`${baseURI}${recordId}`);
    });

    it("Should fail to mint an NFT without sufficient mint fee", async function () {
        const recordId = 2;

        await expect(
            campaignNFT.connect(addr1).mintRecord(recordId, {
                value: ethers.parseEther("0.005"), // Insufficient mint fee
            })
        ).to.be.revertedWith("Insufficient minting fee");
    });
});
