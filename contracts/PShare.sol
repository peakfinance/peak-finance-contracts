// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./owner/Operator.sol";

contract PShare is ERC20BurnableUpgradeable, Operator {
    using SafeMathUpgradeable for uint256;

    // TOTAL MAX SUPPLY = 70,000 pSHAREs
    uint256 public constant FARMING_POOL_REWARD_ALLOCATION = 5400000 ether;
    uint256 public constant COMMUNITY_FUND_POOL_ALLOCATION = 1100000 ether;
    uint256 public constant DEV_FUND_POOL_ALLOCATION = 500000 ether;
    uint256 public constant maxFeeAmount = 100 ether;
    address public constant USDC = 0xEA32A96608495e54156Ae48931A7c20f0dcc1a21;

    uint256 public constant VESTING_DURATION = 365 days;
    uint256 public startTime;
    uint256 public endTime;

    uint256 public communityFundRewardRate;
    uint256 public devFundRewardRate;
    uint256 public buybackRate;
    uint256 public treasuryRate;

    address public communityFund;
    address public devFund;

    uint256 public communityFundLastClaimed;
    uint256 public devFundLastClaimed;

    bool public rewardPoolDistributed;
    
    IUniswapV2Router public uniswapV2Router;
    address public uniswapV2Pair;

    function initialize(uint256 _startTime, address _communityFund, address _devFund) public initializer {
        __Operator_init_unchained();
        __ERC20_init_unchained("PRO", "PRO");
        __ERC20Burnable_init_unchained();
        __PShare_init_unchained(_startTime, _communityFund, _devFund);
    }

    function __PShare_init_unchained(uint256 _startTime, address _communityFund, address _devFund) internal onlyInitializing {
        rewardPoolDistributed = false;

        _mint(_msgSender(), 1 ether); // mint 1 PEAK Share for initial pools deployment

        startTime = _startTime;
        endTime = startTime + VESTING_DURATION;

        communityFundLastClaimed = startTime;
        devFundLastClaimed = startTime;

        communityFundRewardRate = COMMUNITY_FUND_POOL_ALLOCATION.div(VESTING_DURATION);
        devFundRewardRate = DEV_FUND_POOL_ALLOCATION.div(VESTING_DURATION);

        rewardPoolDistributed = false;

        require(_devFund != address(0), "Address cannot be 0");
        devFund = _devFund;

        require(_communityFund != address(0), "Address cannot be 0");
        communityFund = _communityFund;

        IUniswapV2Router _uniswapV2Router = IUniswapV2Router(0x1E876cCe41B7b844FDe09E38Fa1cf00f213bFf56);
         // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.Metis());

        // set the rest of the contract variables
        uniswapV2Router = _uniswapV2Router;
    }

    function setTreasuryFund(address _communityFund) external {
        require(_msgSender() == devFund, "!dev");
        communityFund = _communityFund;
    }

    function setDevFund(address _devFund) external {
        require(_msgSender() == devFund, "!dev");
        require(_devFund != address(0), "zero");
        devFund = _devFund;
    }

    function unclaimedTreasuryFund() public view returns (uint256 _pending) {
        uint256 _now = block.timestamp;
        if (_now > endTime) _now = endTime;
        if (communityFundLastClaimed >= _now) return 0;
        _pending = _now.sub(communityFundLastClaimed).mul(communityFundRewardRate);
    }

    function unclaimedDevFund() public view returns (uint256 _pending) {
        uint256 _now = block.timestamp;
        if (_now > endTime) _now = endTime;
        if (devFundLastClaimed >= _now) return 0;
        _pending = _now.sub(devFundLastClaimed).mul(devFundRewardRate);
    }

    /**
     * @dev Claim pending rewards to community and dev fund
     */
    function claimRewards() external {
        uint256 _pending = unclaimedTreasuryFund();
        if (_pending > 0 && communityFund != address(0)) {
            _mint(communityFund, _pending);
            communityFundLastClaimed = block.timestamp;
        }
        _pending = unclaimedDevFund();
        if (_pending > 0 && devFund != address(0)) {
            _mint(devFund, _pending);
            devFundLastClaimed = block.timestamp;
        }
    }

    /**
     * @notice distribute to reward pool (only once)
     */
    function distributeReward(address _farmingIncentiveFund) external onlyOperator {
        require(!rewardPoolDistributed, "only can distribute once");
        require(_farmingIncentiveFund != address(0), "!_farmingIncentiveFund");
        rewardPoolDistributed = true;
        _mint(_farmingIncentiveFund, FARMING_POOL_REWARD_ALLOCATION);
    }

    function burn(uint256 amount) public override {
        super.burn(amount);
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        _token.transfer(_to, _amount);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);


        uint256 currentAllowance = allowance(sender, _msgSender());
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }
        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        uint256 _amount = amount;

        if( sender != communityFund && recipient != communityFund ) {
            uint256 _buyBack = amount.mul(buybackRate).div(100);
            uint256 _treasury = amount.mul(treasuryRate).div(100);
            _amount = _amount.sub(_buyBack).sub(_treasury);

            // PRO Buyback & Burn
            _burn(sender, _buyBack);

            if(address(this).balance >= maxFeeAmount)  {
                // For Sellers
                if (sender == uniswapV2Pair) {
                    uint256 half = _treasury.div(2);
                    swapTokensForMetis(half);
                    swapTokensForTokens(_treasury.sub(half));

                    // Receive Half as Metis into DAO Treasury
                    (bool success, ) = communityFund.call{ value: address(this).balance }("");
                    
                    // Half of 6% as USDC
                    uint256 outputUSDC = IERC20(USDC).balanceOf(address(this));
                    IERC20(USDC).transferFrom(address(this), communityFund, outputUSDC);
                }
                // For Buyers
                if (recipient == uniswapV2Pair) {
                    swapTokensForMetis(_treasury);
                    // All as Metis into DAO Treasury
                    (bool success, ) = communityFund.call{ value: address(this).balance }("");
                }
            }
        }

        super._transfer(sender, recipient, _amount);
    }

    function swapTokensForMetis(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.Metis();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForMetisSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function swapTokensForTokens(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.Metis();
        path[2] = USDC;

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(tokenAmount, 0, path, address(this), block.timestamp);
    }
}
