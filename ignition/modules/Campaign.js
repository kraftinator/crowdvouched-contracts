const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

const CampaignModule = buildModule("CampaignModule", (m) => {
  const campaign = m.contract("Campaign", ["1850 U.S. Census", "1850 United States Census"]);

  return { campaign };
});

module.exports = CampaignModule;