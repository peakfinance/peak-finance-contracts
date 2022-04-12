// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./lib/Babylonian.sol";
import "./owner/Operator.sol";
import "./utils/ContractGuard.sol";
import "./interfaces/IBasisAsset.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IMasonry.sol";
contract Treasury is ContractGuard {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;

    /* ========= CONSTANT VARIABLES ======== */

    uint256 public constant PERIOD = 6 hours;

    /* ========== STATE VARIABLES ========== */

    // governance
    address public operator;

    // flags
    bool public initialized;

    // epoch
    uint256 public startTime;
    uint256 public epoch;
    uint256 public epochSupplyContractionLeft;

    // exclusions from total supply
    address[] public excludedFromTotalSupply;

    // core components
    address public peak;
    address public pbond;
    address public pshare;

    address public masonry;
    address public peakOracle;

    // price
    uint256 public peakPriceOne;
    uint256 public peakPriceCeiling;

    uint256 public seigniorageSaved;

    uint256[] public supplyTiers;
    uint256[] public maxExpansionTiers;

    uint256 public maxSupplyExpansionPercent;
    uint256 public bondDepletionFloorPercent;
    uint256 public seigniorageExpansionFloorPercent;
    uint256 public maxSupplyContractionPercent;
    uint256 public maxDebtRatioPercent;

    // 28 first epochs (1 week) with 4.5% expansion regardless of PEAK price
    uint256 public bootstrapEpochs;
    uint256 public bootstrapSupplyExpansionPercent;

    /* =================== Added variables =================== */
    uint256 public previousEpochPeakPrice;
    uint256 public maxDiscountRate; // when purchasing bond
    uint256 public maxPremiumRate; // when redeeming bond
    uint256 public discountPercent;
    uint256 public premiumThreshold;
    uint256 public premiumPercent;
    uint256 public mintingFactorForPayingDebt; // print extra PEAK during debt phase

    address public daoFund;
    uint256 public daoFundSharedPercent;

    address public devFund;
    uint256 public devFundSharedPercent;

    /* =================== Events =================== */

    event Initialized(address indexed executor, uint256 at);
    event BurnedBonds(address indexed from, uint256 bondAmount);
    event RedeemedBonds(address indexed from, uint256 peakAmount, uint256 bondAmount);
    event BoughtBonds(address indexed from, uint256 peakAmount, uint256 bondAmount);
    event TreasuryFunded(uint256 timestamp, uint256 seigniorage);
    event MasonryFunded(uint256 timestamp, uint256 seigniorage);
    event DaoFundFunded(uint256 timestamp, uint256 seigniorage);
    event DevFundFunded(uint256 timestamp, uint256 seigniorage);

    function initialize() public initializer {
        __Context_init_unchained();
        __Treasury_init_unchained();
    }

    function __Treasury_init_unchained() internal onlyInitializing {
        excludedFromTotalSupply = [
            address(0x9A896d3c54D7e45B558BD5fFf26bF1E8C031F93b), // PeakGenesisPool
            address(0xa7b9123f4b15fE0fF01F469ff5Eab2b41296dC0E), // new PeakRewardPool
            address(0xA7B16703470055881e7EE093e9b0bF537f29CD4d) // old PeakRewardPool
        ];
    }

    /* =================== Modifier =================== */

    modifier onlyOperator() {
        require(operator == _msgSender(), "Treasury: caller is not the operator");
        _;
    }

    modifier checkCondition {
        require(block.timestamp >= startTime, "Treasury: not started yet");

        _;
    }

    modifier checkEpoch {
        require(block.timestamp >= nextEpochPoint(), "Treasury: not opened yet");

        _;

        epoch = epoch.add(1);
        epochSupplyContractionLeft = (getPeakPrice() > peakPriceCeiling) ? 0 : getPeakCirculatingSupply().mul(maxSupplyContractionPercent).div(10000);
    }

    modifier checkOperator {
        require(
            IBasisAsset(peak).operator() == address(this) &&
                IBasisAsset(pbond).operator() == address(this) &&
                IBasisAsset(pshare).operator() == address(this) &&
                Operator(masonry).operator() == address(this),
            "Treasury: need more permission"
        );

        _;
    }

    modifier notInitialized {
        require(!initialized, "Treasury: already initialized");

        _;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function isInitialized() public view returns (bool) {
        return initialized;
    }

    // epoch
    function nextEpochPoint() public view returns (uint256) {
        return startTime.add(epoch.mul(PERIOD));
    }

    // oracle
    function getPeakPrice() public view returns (uint256 peakPrice) {
        try IOracle(peakOracle).consult(peak, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult PEAK price from the oracle");
        }
    }

    function getPeakUpdatedPrice() public view returns (uint256 _peakPrice) {
        try IOracle(peakOracle).twap(peak, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult PEAK price from the oracle");
        }
    }

    // budget
    function getReserve() public view returns (uint256) {
        return seigniorageSaved;
    }

    function getBurnablePeakLeft() public view returns (uint256 _burnablePeakLeft) {
        uint256 _peakPrice = getPeakPrice();
        if (_peakPrice <= peakPriceOne) {
            uint256 _peakSupply = getPeakCirculatingSupply();
            uint256 _bondMaxSupply = _peakSupply.mul(maxDebtRatioPercent).div(10000);
            uint256 _bondSupply = IERC20Upgradeable(pbond).totalSupply();
            if (_bondMaxSupply > _bondSupply) {
                uint256 _maxMintableBond = _bondMaxSupply.sub(_bondSupply);
                uint256 _maxBurnablePeak = _maxMintableBond.mul(_peakPrice).div(1e18);
                _burnablePeakLeft = Math.min(epochSupplyContractionLeft, _maxBurnablePeak);
            }
        }
    }

    function getRedeemableBonds() public view returns (uint256 _redeemableBonds) {
        uint256 _peakPrice = getPeakPrice();
        if (_peakPrice > peakPriceCeiling) {
            uint256 _totalPeak = IERC20Upgradeable(peak).balanceOf(address(this));
            uint256 _rate = getBondPremiumRate();
            if (_rate > 0) {
                _redeemableBonds = _totalPeak.mul(1e18).div(_rate);
            }
        }
    }

    function getBondDiscountRate() public view returns (uint256 _rate) {
        uint256 _peakPrice = getPeakPrice();
        if (_peakPrice <= peakPriceOne) {
            if (discountPercent == 0) {
                // no discount
                _rate = peakPriceOne;
            } else {
                uint256 _bondAmount = peakPriceOne.mul(1e18).div(_peakPrice); // to burn 1 PEAK
                uint256 _discountAmount = _bondAmount.sub(peakPriceOne).mul(discountPercent).div(10000);
                _rate = peakPriceOne.add(_discountAmount);
                if (maxDiscountRate > 0 && _rate > maxDiscountRate) {
                    _rate = maxDiscountRate;
                }
            }
        }
    }

    function getBondPremiumRate() public view returns (uint256 _rate) {
        uint256 _peakPrice = getPeakPrice();
        if (_peakPrice > peakPriceCeiling) {
            uint256 _peakPricePremiumThreshold = peakPriceOne.mul(premiumThreshold).div(100);
            if (_peakPrice >= _peakPricePremiumThreshold) {
                //Price > 1.10
                uint256 _premiumAmount = _peakPrice.sub(peakPriceOne).mul(premiumPercent).div(10000);
                _rate = peakPriceOne.add(_premiumAmount);
                if (maxPremiumRate > 0 && _rate > maxPremiumRate) {
                    _rate = maxPremiumRate;
                }
            } else {
                // no premium bonus
                _rate = peakPriceOne;
            }
        }
    }

    /* ========== GOVERNANCE ========== */

    function initializeTreasury(
        address _peak,
        address _pbond,
        address _pshare,
        address _peakOracle,
        address _masonry,
        uint256 _startTime
    ) public notInitialized {
        peak = _peak;
        pbond = _pbond;
        pshare = _pshare;
        peakOracle = _peakOracle;
        masonry = _masonry;
        startTime = _startTime;

        peakPriceOne = 10**18;
        peakPriceCeiling = peakPriceOne.mul(101).div(100);
        // Dynamic max expansion percent
        supplyTiers = [0 ether, 500000 ether, 1000000 ether, 1500000 ether, 2000000 ether, 5000000 ether, 10000000 ether, 20000000 ether, 50000000 ether];
        maxExpansionTiers = [450, 400, 350, 300, 250, 200, 150, 125, 100];

        maxSupplyExpansionPercent = 400; // Upto 4.0% supply for expansion

        bondDepletionFloorPercent = 10000; // 100% of Bond supply for depletion floor
        seigniorageExpansionFloorPercent = 3500; // At least 35% of expansion reserved for masonry
        maxSupplyContractionPercent = 300; // Upto 3.0% supply for contraction (to burn PEAK and mint pBOND)
        maxDebtRatioPercent = 3500; // Upto 35% supply of pBOND to purchase

        premiumThreshold = 110;
        premiumPercent = 7000;

        // First 28 epochs with 4.5% expansion
        bootstrapEpochs = 28;
        bootstrapSupplyExpansionPercent = 450;

        // set seigniorageSaved to it's balance
        seigniorageSaved = IERC20Upgradeable(peak).balanceOf(address(this));

        initialized = true;
        operator = _msgSender();
        emit Initialized(_msgSender(), block.number);
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setMasonry(address _masonry) external onlyOperator {
        masonry = _masonry;
    }
    function setPeakOracle(address _peakOracle) external onlyOperator {
        peakOracle = _peakOracle;
    }

    function setPeakPriceCeiling(uint256 _peakPriceCeiling) external onlyOperator {
        require(_peakPriceCeiling >= peakPriceOne && _peakPriceCeiling <= peakPriceOne.mul(120).div(100), "out of range"); // [$1.0, $1.2]
        peakPriceCeiling = _peakPriceCeiling;
    }

    function setMaxSupplyExpansionPercents(uint256 _maxSupplyExpansionPercent) external onlyOperator {
        require(_maxSupplyExpansionPercent >= 10 && _maxSupplyExpansionPercent <= 1000, "_maxSupplyExpansionPercent: out of range"); // [0.1%, 10%]
        maxSupplyExpansionPercent = _maxSupplyExpansionPercent;
    }

    function setSupplyTiersEntry(uint8 _index, uint256 _value) external onlyOperator returns (bool) {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < 9, "Index has to be lower than count of tiers");
        if (_index > 0) {
            require(_value > supplyTiers[_index - 1]);
        }
        if (_index < 8) {
            require(_value < supplyTiers[_index + 1]);
        }
        supplyTiers[_index] = _value;
        return true;
    }

    function setMaxExpansionTiersEntry(uint8 _index, uint256 _value) external onlyOperator returns (bool) {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < 9, "Index has to be lower than count of tiers");
        require(_value >= 10 && _value <= 1000, "_value: out of range"); // [0.1%, 10%]
        maxExpansionTiers[_index] = _value;
        return true;
    }

    function setBondDepletionFloorPercent(uint256 _bondDepletionFloorPercent) external onlyOperator {
        require(_bondDepletionFloorPercent >= 500 && _bondDepletionFloorPercent <= 10000, "out of range"); // [5%, 100%]
        bondDepletionFloorPercent = _bondDepletionFloorPercent;
    }

    function setMaxSupplyContractionPercent(uint256 _maxSupplyContractionPercent) external onlyOperator {
        require(_maxSupplyContractionPercent >= 100 && _maxSupplyContractionPercent <= 1500, "out of range"); // [0.1%, 15%]
        maxSupplyContractionPercent = _maxSupplyContractionPercent;
    }

    function setMaxDebtRatioPercent(uint256 _maxDebtRatioPercent) external onlyOperator {
        require(_maxDebtRatioPercent >= 1000 && _maxDebtRatioPercent <= 10000, "out of range"); // [10%, 100%]
        maxDebtRatioPercent = _maxDebtRatioPercent;
    }

    function setBootstrap(uint256 _bootstrapEpochs, uint256 _bootstrapSupplyExpansionPercent) external onlyOperator {
        require(_bootstrapEpochs <= 120, "_bootstrapEpochs: out of range"); // <= 1 month
        require(_bootstrapSupplyExpansionPercent >= 100 && _bootstrapSupplyExpansionPercent <= 1000, "_bootstrapSupplyExpansionPercent: out of range"); // [1%, 10%]
        bootstrapEpochs = _bootstrapEpochs;
        bootstrapSupplyExpansionPercent = _bootstrapSupplyExpansionPercent;
    }

    function setExtraFunds(
        address _daoFund,
        uint256 _daoFundSharedPercent,
        address _devFund,
        uint256 _devFundSharedPercent
    ) external onlyOperator {
        require(_daoFund != address(0), "zero");
        require(_daoFundSharedPercent <= 3000, "out of range"); // <= 30%
        require(_devFund != address(0), "zero");
        require(_devFundSharedPercent <= 1000, "out of range"); // <= 10%
        daoFund = _daoFund;
        daoFundSharedPercent = _daoFundSharedPercent;
        devFund = _devFund;
        devFundSharedPercent = _devFundSharedPercent;
    }

    function setMaxDiscountRate(uint256 _maxDiscountRate) external onlyOperator {
        maxDiscountRate = _maxDiscountRate;
    }

    function setMaxPremiumRate(uint256 _maxPremiumRate) external onlyOperator {
        maxPremiumRate = _maxPremiumRate;
    }

    function setDiscountPercent(uint256 _discountPercent) external onlyOperator {
        require(_discountPercent <= 20000, "_discountPercent is over 200%");
        discountPercent = _discountPercent;
    }

    function setPremiumThreshold(uint256 _premiumThreshold) external onlyOperator {
        require(_premiumThreshold >= peakPriceCeiling, "_premiumThreshold exceeds peakPriceCeiling");
        require(_premiumThreshold <= 150, "_premiumThreshold is higher than 1.5");
        premiumThreshold = _premiumThreshold;
    }

    function setPremiumPercent(uint256 _premiumPercent) external onlyOperator {
        require(_premiumPercent <= 20000, "_premiumPercent is over 200%");
        premiumPercent = _premiumPercent;
    }

    function setMintingFactorForPayingDebt(uint256 _mintingFactorForPayingDebt) external onlyOperator {
        require(_mintingFactorForPayingDebt >= 10000 && _mintingFactorForPayingDebt <= 20000, "_mintingFactorForPayingDebt: out of range"); // [100%, 200%]
        mintingFactorForPayingDebt = _mintingFactorForPayingDebt;
    }

    /* ========== MUTABLE FUNCTIONS ========== */

    function _updatePeakPrice() internal {
        try IOracle(peakOracle).update() {} catch {}
    }

    function getPeakCirculatingSupply() public view returns (uint256) {
        IERC20Upgradeable peakErc20 = IERC20Upgradeable(peak);
        uint256 totalSupply = peakErc20.totalSupply();
        uint256 balanceExcluded = 0;
        for (uint8 entryId = 0; entryId < excludedFromTotalSupply.length; ++entryId) {
            balanceExcluded = balanceExcluded.add(peakErc20.balanceOf(excludedFromTotalSupply[entryId]));
        }
        return totalSupply.sub(balanceExcluded);
    }

    function buyBonds(uint256 _peakAmount, uint256 targetPrice) external onlyOneBlock checkCondition checkOperator {
        require(_peakAmount > 0, "Treasury: cannot purchase bonds with zero amount");

        uint256 peakPrice = getPeakPrice();
        require(peakPrice == targetPrice, "Treasury: PEAK price moved");
        require(
            peakPrice < peakPriceOne, // price < $1
            "Treasury: peakPrice not eligible for bond purchase"
        );

        require(_peakAmount <= epochSupplyContractionLeft, "Treasury: not enough bond left to purchase");

        uint256 _rate = getBondDiscountRate();
        require(_rate > 0, "Treasury: invalid bond rate");

        uint256 _bondAmount = _peakAmount.mul(_rate).div(1e18);
        uint256 peakSupply = getPeakCirculatingSupply();
        uint256 newBondSupply = IERC20Upgradeable(pbond).totalSupply().add(_bondAmount);
        require(newBondSupply <= peakSupply.mul(maxDebtRatioPercent).div(10000), "over max debt ratio");

        IBasisAsset(peak).burnFrom(_msgSender(), _peakAmount);
        IBasisAsset(pbond).mint(_msgSender(), _bondAmount);

        epochSupplyContractionLeft = epochSupplyContractionLeft.sub(_peakAmount);
        _updatePeakPrice();

        emit BoughtBonds(_msgSender(), _peakAmount, _bondAmount);
    }

    function redeemBonds(uint256 _bondAmount, uint256 targetPrice) external onlyOneBlock checkCondition checkOperator {
        require(_bondAmount > 0, "Treasury: cannot redeem bonds with zero amount");

        uint256 peakPrice = getPeakPrice();
        require(peakPrice == targetPrice, "Treasury: PEAK price moved");
        require(
            peakPrice > peakPriceCeiling, // price > $1.01
            "Treasury: peakPrice not eligible for bond purchase"
        );

        uint256 _rate = getBondPremiumRate();
        require(_rate > 0, "Treasury: invalid bond rate");

        uint256 _peakAmount = _bondAmount.mul(_rate).div(1e18);
        require(IERC20Upgradeable(peak).balanceOf(address(this)) >= _peakAmount, "Treasury: treasury has no more budget");

        seigniorageSaved = seigniorageSaved.sub(Math.min(seigniorageSaved, _peakAmount));

        IBasisAsset(pbond).burnFrom(_msgSender(), _bondAmount);
        IERC20Upgradeable(peak).safeTransfer(_msgSender(), _peakAmount);

        _updatePeakPrice();

        emit RedeemedBonds(_msgSender(), _peakAmount, _bondAmount);
    }

    function _sendToMasonry(uint256 _amount) internal {
        IBasisAsset(peak).mint(address(this), _amount);

        uint256 _daoFundSharedAmount = 0;
        if (daoFundSharedPercent > 0) {
            _daoFundSharedAmount = _amount.mul(daoFundSharedPercent).div(10000);
            IERC20Upgradeable(peak).transfer(daoFund, _daoFundSharedAmount);
            emit DaoFundFunded(block.timestamp, _daoFundSharedAmount);
        }

        uint256 _devFundSharedAmount = 0;
        if (devFundSharedPercent > 0) {
            _devFundSharedAmount = _amount.mul(devFundSharedPercent).div(10000);
            IERC20Upgradeable(peak).transfer(devFund, _devFundSharedAmount);
            emit DevFundFunded(block.timestamp, _devFundSharedAmount);
        }

        _amount = _amount.sub(_daoFundSharedAmount).sub(_devFundSharedAmount);

        IERC20Upgradeable(peak).safeApprove(masonry, 0);
        IERC20Upgradeable(peak).safeApprove(masonry, _amount);
        IMasonry(masonry).allocateSeigniorage(_amount);
        emit MasonryFunded(block.timestamp, _amount);
    }

    function _calculateMaxSupplyExpansionPercent(uint256 _peakSupply) internal returns (uint256) {
        for (uint8 tierId = 8; tierId >= 0; --tierId) {
            if (_peakSupply >= supplyTiers[tierId]) {
                maxSupplyExpansionPercent = maxExpansionTiers[tierId];
                break;
            }
        }
        return maxSupplyExpansionPercent;
    }

    function allocateSeigniorage() external onlyOneBlock checkCondition checkEpoch checkOperator {
        _updatePeakPrice();
        previousEpochPeakPrice = getPeakPrice();
        uint256 peakSupply = getPeakCirculatingSupply().sub(seigniorageSaved);
        if (epoch < bootstrapEpochs) {
            // 28 first epochs with 4.5% expansion
            _sendToMasonry(peakSupply.mul(bootstrapSupplyExpansionPercent).div(10000));
        } else {
            if (previousEpochPeakPrice > peakPriceCeiling) {
                // Expansion ($PEAK Price > 1 $METIS): there is some seigniorage to be allocated
                uint256 bondSupply = IERC20Upgradeable(pbond).totalSupply();
                uint256 _percentage = previousEpochPeakPrice.sub(peakPriceOne);
                uint256 _savedForBond;
                uint256 _savedForMasonry;
                uint256 _mse = _calculateMaxSupplyExpansionPercent(peakSupply).mul(1e14);
                if (_percentage > _mse) {
                    _percentage = _mse;
                }
                if (seigniorageSaved >= bondSupply.mul(bondDepletionFloorPercent).div(10000)) {
                    // saved enough to pay debt, mint as usual rate
                    _savedForMasonry = peakSupply.mul(_percentage).div(1e18);
                } else {
                    // have not saved enough to pay debt, mint more
                    uint256 _seigniorage = peakSupply.mul(_percentage).div(1e18);
                    _savedForMasonry = _seigniorage.mul(seigniorageExpansionFloorPercent).div(10000);
                    _savedForBond = _seigniorage.sub(_savedForMasonry);
                    if (mintingFactorForPayingDebt > 0) {
                        _savedForBond = _savedForBond.mul(mintingFactorForPayingDebt).div(10000);
                    }
                }
                if (_savedForMasonry > 0) {
                    _sendToMasonry(_savedForMasonry);
                }
                if (_savedForBond > 0) {
                    seigniorageSaved = seigniorageSaved.add(_savedForBond);
                    IBasisAsset(peak).mint(address(this), _savedForBond);
                    emit TreasuryFunded(block.timestamp, _savedForBond);
                }
            }
        }
    }

    function governanceRecoverUnsupported(
        IERC20Upgradeable _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        // do not allow to drain core tokens
        require(address(_token) != address(peak), "peak");
        require(address(_token) != address(pbond), "bond");
        require(address(_token) != address(pshare), "share");
        _token.safeTransfer(_to, _amount);
    }

    function masonrySetOperator(address _operator) external onlyOperator {
        IMasonry(masonry).setOperator(_operator);
    }

    function masonrySetLockUp(uint256 _withdrawLockupEpochs, uint256 _rewardLockupEpochs) external onlyOperator {
        IMasonry(masonry).setLockUp(_withdrawLockupEpochs, _rewardLockupEpochs);
    }

    function masonryAllocateSeigniorage(uint256 amount) external onlyOperator {
        IMasonry(masonry).allocateSeigniorage(amount);
    }

    function masonryGovernanceRecoverUnsupported(
        address _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        IMasonry(masonry).governanceRecoverUnsupported(_token, _amount, _to);
    }
}
