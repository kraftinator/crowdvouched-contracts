const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

const CampaignModule = buildModule("CampaignModule", (m) => {
  const campaign = m.contract(
    "Campaign", 
    [
      "1850 U.S. Census", 
      "1850 United States Census", 
      "U.S. Census 1850 Token", 
      "USC1850",
      "https://arweave.net/SRk92t3iZswEvhBnXoVOk9YlUtxkHfPcImyWuJNLJZg/",
      "U.S. Census 1850 NFT",
      "USC1850NFT",
      ethers.parseEther("0.01")
    ]
  );
  
  return { campaign };
});

module.exports = CampaignModule;