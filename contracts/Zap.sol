// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IHyperswapRouter01.sol";

import "./lib/TransferHelper.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IVault is IERC20Upgradeable {
    function deposit(uint256 amount) external;

    function withdraw(uint256 shares) external;

    function want() external pure returns (address);
}

contract Zap is OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ========== STATE VARIABLES ========== */

    address private constant WNATIVE = address(0xDeadDeAddeAddEAddeadDEaDDEAdDeaDDeAD0000);
    address private FEE_TO_ADDR;
    uint16 FEE_RATE;
    uint16 MIN_AMT;
    mapping(address => mapping(address => address))
        private tokenBridgeForRouter;

    event FeeChange(address fee_to, uint16 rate, uint16 min);

    mapping(address => bool) public useNativeRouter;

    function initialize() public initializer {
        __Ownable_init_unchained();
        __Zap_init_unchained();
    }

    function __Zap_init_unchained() internal onlyInitializing {
        FEE_TO_ADDR = _msgSender();
        FEE_RATE = 330;
        MIN_AMT = 10000;
    }

    /* ========== External Functions ========== */

    receive() external payable {}

    function zapInToken(
        address _from,
        uint256 amount,
        address _to,
        address routerAddr,
        address _recipient
    ) external {
        // From an ERC20 to an LP token, through specified router, going through base asset if necessary
        IERC20Upgradeable(_from).safeTransferFrom(
            _msgSender(),
            address(this),
            amount
        );
        // we'll need this approval to add liquidity
        _approveTokenIfNeeded(_from, routerAddr);
        _swapTokenToLP(_from, amount, _to, _recipient, routerAddr);
    }

    function estimateZapInToken(
        address _from,
        address _to,
        address _router,
        uint256 _amt
    ) public view returns (uint256, uint256) {
        // get pairs for desired lp
        if (
            _from == IUniswapV2Pair(_to).token0() ||
            _from == IUniswapV2Pair(_to).token1()
        ) {
            // check if we already have one of the assets
            // if so, we're going to sell half of _from for the other token we need
            // figure out which token we need, and approve
            address other = _from == IUniswapV2Pair(_to).token0()
                ? IUniswapV2Pair(_to).token1()
                : IUniswapV2Pair(_to).token0();
            // calculate amount of _from to sell
            uint256 sellAmount = _amt.div(2);
            // execute swap
            uint256 otherAmount = _estimateSwap(
                _from,
                sellAmount,
                other,
                _router
            );
            if (_from == IUniswapV2Pair(_to).token0()) {
                return (sellAmount, otherAmount);
            } else {
                return (otherAmount, sellAmount);
            }
        } else {
            // go through native token for highest liquidity
            uint256 nativeAmount = _from == WNATIVE
                ? _amt
                : _estimateSwap(_from, _amt, WNATIVE, _router);
            return estimateZapIn(_to, _router, nativeAmount);
        }
    }

    function zapIn(
        address _to,
        address routerAddr,
        address _recipient
    ) external payable {
        // from Native to an LP token through the specified router
        _swapNativeToLP(_to, msg.value, _recipient, routerAddr);
    }

    function estimateZapIn(
        address _LP,
        address _router,
        uint256 _amt
    ) public view returns (uint256, uint256) {
        uint256 zapAmt = _amt.div(2);

        IUniswapV2Pair pair = IUniswapV2Pair(_LP);
        address token0 = pair.token0();
        address token1 = pair.token1();

        if (token0 == WNATIVE || token1 == WNATIVE) {
            address token = token0 == WNATIVE ? token1 : token0;
            uint256 tokenAmt = _estimateSwap(WNATIVE, zapAmt, token, _router);
            if (token0 == WNATIVE) {
                return (zapAmt, tokenAmt);
            } else {
                return (tokenAmt, zapAmt);
            }
        } else {
            uint256 token0Amt = _estimateSwap(WNATIVE, zapAmt, token0, _router);
            uint256 token1Amt = _estimateSwap(WNATIVE, zapAmt, token1, _router);

            return (token0Amt, token1Amt);
        }
    }

    function zapAcross(
        address _from,
        uint256 amount,
        address _toRouter,
        address _recipient
    ) external {
        IERC20Upgradeable(_from).safeTransferFrom(
            _msgSender(),
            address(this),
            amount
        );

        IUniswapV2Pair pair = IUniswapV2Pair(_from);
        _approveTokenIfNeeded(pair.token0(), _toRouter);
        _approveTokenIfNeeded(pair.token1(), _toRouter);

        IERC20Upgradeable(_from).safeTransfer(_from, amount);
        uint256 amt0;
        uint256 amt1;
        (amt0, amt1) = pair.burn(address(this));
        IUniswapV2Router(_toRouter).addLiquidity(
            pair.token0(),
            pair.token1(),
            amt0,
            amt1,
            0,
            0,
            _recipient,
            block.timestamp
        );
    }

    function zapOut(
        address _from,
        uint256 amount,
        address routerAddr,
        address _recipient
    ) external {
        // from an LP token to Native through specified router
        // take the LP token
        IERC20Upgradeable(_from).safeTransferFrom(
            _msgSender(),
            address(this),
            amount
        );
        _approveTokenIfNeeded(_from, routerAddr);

        // get pairs for LP
        address token0 = IUniswapV2Pair(_from).token0();
        address token1 = IUniswapV2Pair(_from).token1();
        _approveTokenIfNeeded(token0, routerAddr);
        _approveTokenIfNeeded(token1, routerAddr);
        // check if either is already native token
        if (token0 == WNATIVE || token1 == WNATIVE) {
            // if so, we only need to swap one, figure out which and how much
            address token = token0 != WNATIVE ? token0 : token1;
            uint256 amtToken;
            uint256 amtETH;
            (amtToken, amtETH) = IUniswapV2Router(routerAddr)
                .removeLiquidityMetis(
                    token,
                    amount,
                    0,
                    0,
                    address(this),
                    block.timestamp
                );
            // swap with _msgSender() as recipient, so they already get the Native
            _swapTokenForNative(token, amtToken, _recipient, routerAddr);
            // send other half of Native
            TransferHelper.safeTransferETH(_recipient, amtETH);
        } else {
            // convert both for Native with _msgSender() as recipient
            uint256 amt0;
            uint256 amt1;
            (amt0, amt1) = IUniswapV2Router(routerAddr).removeLiquidity(
                token0,
                token1,
                amount,
                0,
                0,
                address(this),
                block.timestamp
            );
            _swapTokenForNative(token0, amt0, _recipient, routerAddr);
            _swapTokenForNative(token1, amt1, _recipient, routerAddr);
        }
    }

    function zapOutToken(
        address _from,
        uint256 amount,
        address _to,
        address routerAddr,
        address _recipient
    ) external {
        // from an LP token to an ERC20 through specified router
        IERC20Upgradeable(_from).safeTransferFrom(
            _msgSender(),
            address(this),
            amount
        );
        _approveTokenIfNeeded(_from, routerAddr);

        address token0 = IUniswapV2Pair(_from).token0();
        address token1 = IUniswapV2Pair(_from).token1();
        _approveTokenIfNeeded(token0, routerAddr);
        _approveTokenIfNeeded(token1, routerAddr);
        uint256 amt0;
        uint256 amt1;
        (amt0, amt1) = IUniswapV2Router(routerAddr).removeLiquidity(
            token0,
            token1,
            amount,
            0,
            0,
            address(this),
            block.timestamp
        );
        if (token0 != _to) {
            amt0 = _swap(token0, amt0, _to, address(this), routerAddr);
        }
        if (token1 != _to) {
            amt1 = _swap(token1, amt1, _to, address(this), routerAddr);
        }
        IERC20Upgradeable(_to).safeTransfer(_recipient, amt0.add(amt1));
    }

    function swapToken(
        address _from,
        uint256 amount,
        address _to,
        address routerAddr,
        address _recipient
    ) external {
        IERC20Upgradeable(_from).safeTransferFrom(
            _msgSender(),
            address(this),
            amount
        );
        _approveTokenIfNeeded(_from, routerAddr);
        _swap(_from, amount, _to, _recipient, routerAddr);
    }

    function swapToNative(
        address _from,
        uint256 amount,
        address routerAddr,
        address _recipient
    ) external {
        IERC20Upgradeable(_from).safeTransferFrom(
            _msgSender(),
            address(this),
            amount
        );
        _approveTokenIfNeeded(_from, routerAddr);
        _swapTokenForNative(_from, amount, _recipient, routerAddr);
    }

    /* ========== Private Functions ========== */

    function _approveTokenIfNeeded(address token, address router) private {
        if (IERC20Upgradeable(token).allowance(address(this), router) == 0) {
            IERC20Upgradeable(token).safeApprove(router, type(uint256).max);
        }
    }

    function _swapTokenToLP(
        address _from,
        uint256 amount,
        address _to,
        address recipient,
        address routerAddr
    ) private returns (uint256) {
        // get pairs for desired lp
        if (
            _from == IUniswapV2Pair(_to).token0() ||
            _from == IUniswapV2Pair(_to).token1()
        ) {
            // check if we already have one of the assets
            // if so, we're going to sell half of _from for the other token we need
            // figure out which token we need, and approve
            address other = _from == IUniswapV2Pair(_to).token0()
                ? IUniswapV2Pair(_to).token1()
                : IUniswapV2Pair(_to).token0();
            _approveTokenIfNeeded(other, routerAddr);
            // calculate amount of _from to sell
            uint256 sellAmount = amount.div(2);
            // execute swap
            uint256 otherAmount = _swap(
                _from,
                sellAmount,
                other,
                address(this),
                routerAddr
            );
            uint256 liquidity;
            (, , liquidity) = IUniswapV2Router(routerAddr).addLiquidity(
                _from,
                other,
                amount.sub(sellAmount),
                otherAmount,
                0,
                0,
                recipient,
                block.timestamp
            );
            return liquidity;
        } else {
            // go through native token for highest liquidity
            uint256 nativeAmount = _swapTokenForNative(
                _from,
                amount,
                address(this),
                routerAddr
            );
            return _swapNativeToLP(_to, nativeAmount, recipient, routerAddr);
        }
    }

    function _swapNativeToLP(
        address _LP,
        uint256 amount,
        address recipient,
        address routerAddress
    ) private returns (uint256) {
        // LP
        IUniswapV2Pair pair = IUniswapV2Pair(_LP);
        address token0 = pair.token0();
        address token1 = pair.token1();
        uint256 liquidity;
        if (token0 == WNATIVE || token1 == WNATIVE) {
            address token = token0 == WNATIVE ? token1 : token0;
            (, , liquidity) = _swapHalfNativeAndProvide(
                token,
                amount,
                routerAddress,
                recipient
            );
        } else {
            (, , liquidity) = _swapNativeToEqualTokensAndProvide(
                token0,
                token1,
                amount,
                routerAddress,
                recipient
            );
        }
        return liquidity;
    }

    function _swapHalfNativeAndProvide(
        address token,
        uint256 amount,
        address routerAddress,
        address recipient
    )
        private
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 swapValue = amount.div(2);
        uint256 tokenAmount = _swapNativeForToken(
            token,
            swapValue,
            address(this),
            routerAddress
        );
        _approveTokenIfNeeded(token, routerAddress);
        if (useNativeRouter[routerAddress]) {
            IHyperswapRouter01 router = IHyperswapRouter01(routerAddress);
            return
                router.addLiquidityMETIS{value: amount.sub(swapValue)}(
                    token,
                    tokenAmount,
                    0,
                    0,
                    recipient,
                    block.timestamp
                );
        } else {
            IUniswapV2Router router = IUniswapV2Router(routerAddress);
            return
                router.addLiquidityMetis{value: amount.sub(swapValue)}(
                    token,
                    tokenAmount,
                    0,
                    0,
                    recipient,
                    block.timestamp
                );
        }
    }

    function _swapNativeToEqualTokensAndProvide(
        address token0,
        address token1,
        uint256 amount,
        address routerAddress,
        address recipient
    )
        private
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 swapValue = amount.div(2);
        uint256 token0Amount = _swapNativeForToken(
            token0,
            swapValue,
            address(this),
            routerAddress
        );
        uint256 token1Amount = _swapNativeForToken(
            token1,
            amount.sub(swapValue),
            address(this),
            routerAddress
        );
        _approveTokenIfNeeded(token0, routerAddress);
        _approveTokenIfNeeded(token1, routerAddress);
        IUniswapV2Router router = IUniswapV2Router(routerAddress);
        return
            router.addLiquidity(
                token0,
                token1,
                token0Amount,
                token1Amount,
                0,
                0,
                recipient,
                block.timestamp
            );
    }

    function _swapNativeForToken(
        address token,
        uint256 value,
        address recipient,
        address routerAddr
    ) private returns (uint256) {
        address[] memory path;
        IUniswapV2Router router = IUniswapV2Router(routerAddr);

        if (tokenBridgeForRouter[token][routerAddr] != address(0)) {
            path = new address[](3);
            path[0] = WNATIVE;
            path[1] = tokenBridgeForRouter[token][routerAddr];
            path[2] = token;
        } else {
            path = new address[](2);
            path[0] = WNATIVE;
            path[1] = token;
        }

        uint256[] memory amounts = router.swapExactMetisForTokens{value: value}(
            0,
            path,
            recipient,
            block.timestamp
        );
        return amounts[amounts.length - 1];
    }

    function _swapTokenForNative(
        address token,
        uint256 amount,
        address recipient,
        address routerAddr
    ) private returns (uint256) {
        address[] memory path;
        IUniswapV2Router router = IUniswapV2Router(routerAddr);

        if (tokenBridgeForRouter[token][routerAddr] != address(0)) {
            path = new address[](3);
            path[0] = token;
            path[1] = tokenBridgeForRouter[token][routerAddr];
            path[2] = router.Metis();
        } else {
            path = new address[](2);
            path[0] = token;
            path[1] = router.Metis();
        }

        uint256[] memory amounts = router.swapExactTokensForMetis(
            amount,
            0,
            path,
            recipient,
            block.timestamp
        );
        return amounts[amounts.length - 1];
    }

    function _swap(
        address _from,
        uint256 amount,
        address _to,
        address recipient,
        address routerAddr
    ) private returns (uint256) {
        IUniswapV2Router router = IUniswapV2Router(routerAddr);

        address fromBridge = tokenBridgeForRouter[_from][routerAddr];
        address toBridge = tokenBridgeForRouter[_to][routerAddr];

        address[] memory path;

        if (fromBridge != address(0) && toBridge != address(0)) {
            if (fromBridge != toBridge) {
                path = new address[](5);
                path[0] = _from;
                path[1] = fromBridge;
                path[2] = WNATIVE;
                path[3] = toBridge;
                path[4] = _to;
            } else {
                path = new address[](3);
                path[0] = _from;
                path[1] = fromBridge;
                path[2] = _to;
            }
        } else if (fromBridge != address(0)) {
            if (_to == WNATIVE) {
                path = new address[](3);
                path[0] = _from;
                path[1] = fromBridge;
                path[2] = WNATIVE;
            } else {
                path = new address[](4);
                path[0] = _from;
                path[1] = fromBridge;
                path[2] = WNATIVE;
                path[3] = _to;
            }
        } else if (toBridge != address(0)) {
            path = new address[](4);
            path[0] = _from;
            path[1] = WNATIVE;
            path[2] = toBridge;
            path[3] = _to;
        } else if (_from == WNATIVE || _to == WNATIVE) {
            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else {
            // Go through WNative
            path = new address[](3);
            path[0] = _from;
            path[1] = WNATIVE;
            path[2] = _to;
        }

        uint256[] memory amounts = router.swapExactTokensForTokens(
            amount,
            0,
            path,
            recipient,
            block.timestamp
        );
        return amounts[amounts.length - 1];
    }

    function _estimateSwap(
        address _from,
        uint256 amount,
        address _to,
        address routerAddr
    ) private view returns (uint256) {
        IUniswapV2Router router = IUniswapV2Router(routerAddr);

        address fromBridge = tokenBridgeForRouter[_from][routerAddr];
        address toBridge = tokenBridgeForRouter[_to][routerAddr];

        address[] memory path;

        if (fromBridge != address(0) && toBridge != address(0)) {
            if (fromBridge != toBridge) {
                path = new address[](5);
                path[0] = _from;
                path[1] = fromBridge;
                path[2] = WNATIVE;
                path[3] = toBridge;
                path[4] = _to;
            } else {
                path = new address[](3);
                path[0] = _from;
                path[1] = fromBridge;
                path[2] = _to;
            }
        } else if (fromBridge != address(0)) {
            if (_to == WNATIVE) {
                path = new address[](3);
                path[0] = _from;
                path[1] = fromBridge;
                path[2] = WNATIVE;
            } else {
                path = new address[](4);
                path[0] = _from;
                path[1] = fromBridge;
                path[2] = WNATIVE;
                path[3] = _to;
            }
        } else if (toBridge != address(0)) {
            path = new address[](4);
            path[0] = _from;
            path[1] = WNATIVE;
            path[2] = toBridge;
            path[3] = _to;
        } else if (_from == WNATIVE || _to == WNATIVE) {
            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else {
            // Go through WNative
            path = new address[](3);
            path[0] = _from;
            path[1] = WNATIVE;
            path[2] = _to;
        }

        uint256[] memory amounts = router.getAmountsOut(amount, path);
        return amounts[amounts.length - 1];
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setTokenBridgeForRouter(
        address token,
        address router,
        address bridgeToken
    ) external onlyOwner {
        tokenBridgeForRouter[token][router] = bridgeToken;
    }

    function withdraw(address token) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(address(this).balance);
            return;
        }

        IERC20Upgradeable(token).transfer(
            owner(),
            IERC20Upgradeable(token).balanceOf(address(this))
        );
    }

    function setUseNativeRouter(address router) external onlyOwner {
        useNativeRouter[router] = true;
    }

    function setFee(
        address addr,
        uint16 rate,
        uint16 min
    ) external onlyOwner {
        require(rate >= 25, "FEE TOO HIGH; MAX FEE = 4%");
        FEE_TO_ADDR = addr;
        FEE_RATE = rate;
        MIN_AMT = min;
        emit FeeChange(addr, rate, min);
    }
}
