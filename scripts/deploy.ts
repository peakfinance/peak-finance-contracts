import { ethers, upgrades } from "hardhat";
// import PeakABI from "../artifacts/contracts/Peak.sol/Peak.json";
// import TreasuryABI from "../artifacts/contracts/Treasury.sol/Treasury.json";
// var Oracle // TODO
// var TombTaxOracle // TODO

async function main() {
  // const devWallet = "0xC549D3d41dAAf88620A06D2f3598FC6a0E19c3c2";
  // const WMetis = "0xDeadDeAddeAddEAddeadDEaDDEAdDeaDDeAD0000";
  // const communityFundWallet = "0xFA6AC7d03e3d5a177BcDd374229014D00761938F";   // Community Fund Wallet
  // const devFundWallet = "0xC549D3d41dAAf88620A06D2f3598FC6a0E19c3c2";         // Dev Fund Wallet
  // const airdropWallet = "0xaf38062846c54BAb3a6d3e5A0AD26830812622bE";
  // const daoWallet = "0xaf38062846c54BAb3a6d3e5A0AD26830812622bE";
  const startTime = 1648731600; // 1st April

  // // PEAK
  // const PeakFactory = await ethers.getContractFactory("Peak");
  // const Peak = await upgrades.deployProxy(PeakFactory, [
  //   0,           // Tax Rate
  //   devWallet,   // Tax Collecter
  // ]);
  // await Peak.deployed();
  // console.log("Peak deployed to:", Peak.address);

  // // PBOND
  // const PBondFactory = await ethers.getContractFactory("PBond");
  // const PBond = await upgrades.deployProxy(PBondFactory, []);
  // await PBond.deployed();
  // console.log("PBond deployed to:", PBond.address);


  // // PRO Token
  // const PShareFactory = await ethers.getContractFactory("PShare");
  // const PShare = await upgrades.deployProxy(PShareFactory, [
  //   startTime,
  //   communityFundWallet,
  //   devFundWallet,
  // ]);
  // await PShare.deployed();
  // console.log("PShare deployed to:", PShare.address);

  // const TreasuryFactory = await ethers.getContractFactory("Treasury");
  // const Treasury = await upgrades.deployProxy(TreasuryFactory, [], { initializer: 'initialize()' });
  // await Treasury.deployed();
  // console.log("Treasury deployed to:", Treasury.address);


  // const MasonryFactory = await ethers.getContractFactory("Masonry");
  // const Masonry = await upgrades.deployProxy(MasonryFactory, [], { initializer: 'initialize()' });
  // await Masonry.deployed();
  // console.log("Masonry deployed to:", Masonry.address);

  // const TaxOfficeFactory = await ethers.getContractFactory("TaxOfficeV2");
  // const TaxOffice = await upgrades.deployProxy(TaxOfficeFactory, [Peak.address], { initializer: 'initialize(address)' });
  // await TaxOffice.deployed();
  // console.log("TaxOffice deployed to:", TaxOffice.address);

  // const ZapFactory = await ethers.getContractFactory("Zap");
  // const Zap = await upgrades.deployProxy(ZapFactory, [], { initializer: 'initialize()' });
  // await Zap.deployed();
  // console.log("Zap deployed to:", Zap.address);

  // const PeakGenesisRewardPoolFactory = await ethers.getContractFactory("PeakGenesisRewardPool");
  // const PeakGenesisRewardPool = await upgrades.deployProxy(PeakGenesisRewardPoolFactory, [Peak.address, startTime], { initializer: 'initialize(address, uint256)' });
  // await PeakGenesisRewardPool.deployed();
  // console.log("PeakGenesisRewardPool deployed to:", PeakGenesisRewardPool.address);

  // const PShareRewardPoolFactory = await ethers.getContractFactory("PShareRewardPool");
  // // Starts After Genesis Pool Ends, Genesis Pool Start Time + 2 Days
  // const PShareRewardPool = await upgrades.deployProxy(PShareRewardPoolFactory, [PShare.address, startTime + 86400 * 16], { initializer: 'initialize(address, uint256)' });
  // await PShareRewardPool.deployed();
  // console.log("PShareReward deployed to:", PShareRewardPool.address);

  // const PeakRewardPoolFactory = await ethers.getContractFactory("PeakRewardPool");
  // const PeakRewardPool = await upgrades.deployProxy(PeakRewardPoolFactory, [Peak.address, startTime + 86400 * 2], { initializer: 'initialize(address, uint256)' });
  // await PeakRewardPool.deployed();
  // console.log("PeakRewardPool deployed to:", PeakRewardPool.address); 

  // const peakPair = await Peak.uniswapV2Pair();
  // const psharePair = await PShare.uniswapV2Pair();
  // console.log("Peak Pair Address: ", peakPair);
  // console.log("PShare Pair Address: ", psharePair);

  // const PShareSwapperFactory = await ethers.getContractFactory("PShareSwapper");
  // const PShareSwapper = await upgrades.deployProxy(PShareSwapperFactory, [Peak.address, PBond.address, PShare.address, WMetis, peakPair, psharePair, daoWallet], { initializer: 'initialize(address, address, address, address, address, address, address)' });
  // await PShareSwapper.deployed();
  // console.log("PShareSwapper deployed to:", PShareSwapper.address);
  
  const accounts = await ethers.getSigners();
  const account = accounts[0];

  // console.log("Distributing Reward");
  // await Peak.transferOperator(account.address);
  // await Peak.distributeReward(PeakGenesisRewardPool.address, PeakRewardPool.address, airdropWallet);
  // console.log("Set Tax Office");
  // await Peak.setTaxOffice(TaxOffice.address);
  // console.log("Distributing Reward : PShare");
  // await PShare.transferOperator(account.address);
  // await PShare.distributeReward(PShareRewardPool.address);
  // await Masonry.initializeMasonry(Peak.address, PShare.address, Treasury.address);
  
  // console.log("Adding Pools");
  // await PeakGenesisRewardPool.add(10000, WMetis, true, startTime);

  // await PeakRewardPool.add(10000, Peak.uniswapV2Pair(), true, startTime + 86400 * 2);

  // await PShareRewardPool.add(6575, Peak.uniswapV2Pair(), true, startTime + 86400 * 16);
  // await PShareRewardPool.add(3425, PShare.uniswapV2Pair(), true, startTime + 86400 * 16);

  // console.log("Operators");
  // await Peak.transferOperator(Treasury.address);
  // await PBond.transferOperator(Treasury.address);
  // await PShare.transferOperator(Treasury.address);

  const Treasury = await ethers.getContractAt("Treasury", "0xc8bc7e9d6602Dc0E21Ac82f8E2a52387860A57ea", account);
  const Peak = await ethers.getContractAt("Peak", "0x1F5550A0F5F659E07506088A7919A88DfF37218f", account);
  const OracleFactory = await ethers.getContractFactory("Oracle");
  const Oracle = await upgrades.deployProxy(OracleFactory, ["0x603e67714A1b910DCCFDcae86dbeC9467de16f4c", "21600", startTime], { initializer: 'initialize(address, uint256, uint256)' });
  await Oracle.deployed();

  console.log("Oracle deployed to:", Oracle.address);
  console.log("Transfer Operator to account");
  await Peak.transferOperator(account.address);
  console.log("Set Peak Oracle");
  await Peak.setPeakOracle(Oracle.address);
  console.log("Revert Operator to Treasury");
  await Peak.transferOperator("0xc8bc7e9d6602Dc0E21Ac82f8E2a52387860A57ea");
  console.log("Initializing");
  await Treasury.initializeTreasury("0x1F5550A0F5F659E07506088A7919A88DfF37218f", "0x59Fd2224cD5A0c5fB99F4858F50a3C469dD22B21", "0x4830e5AAa37001140Ab0Fe628718201c67857608", Oracle.address, "0x9a03e23954578A63791581aed74cE1948871755e", startTime);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
