// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./owner/Operator.sol";
import "./interfaces/ITaxable.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IERC20.sol";

contract TaxOfficeV2 is Operator {
    using SafeMathUpgradeable for uint256;

    address public peak;
    address public constant wmetis = address(0xDeadDeAddeAddEAddeadDEaDDEAdDeaDDeAD0000);
    address public constant uniRouter = address(0x1E876cCe41B7b844FDe09E38Fa1cf00f213bFf56);

    mapping(address => bool) public taxExclusionEnabled;

    function initialize(address _peak) public initializer {
        __Operator_init_unchained();
        __TaxOfficeV2_init_unchained(_peak);
    }

    function __TaxOfficeV2_init_unchained(address _peak) internal onlyInitializing {
        peak = _peak;
    }

    function setTaxTiersTwap(uint8 _index, uint256 _value) public onlyOperator returns (bool) {
        return ITaxable(peak).setTaxTiersTwap(_index, _value);
    }

    function setTaxTiersRate(uint8 _index, uint256 _value) public onlyOperator returns (bool) {
        return ITaxable(peak).setTaxTiersRate(_index, _value);
    }

    function enableAutoCalculateTax() public onlyOperator {
        ITaxable(peak).enableAutoCalculateTax();
    }

    function disableAutoCalculateTax() public onlyOperator {
        ITaxable(peak).disableAutoCalculateTax();
    }

    function setTaxRate(uint256 _taxRate) public onlyOperator {
        ITaxable(peak).setTaxRate(_taxRate);
    }

    function setBurnThreshold(uint256 _burnThreshold) public onlyOperator {
        ITaxable(peak).setBurnThreshold(_burnThreshold);
    }

    function setTaxCollectorAddress(address _taxCollectorAddress) public onlyOperator {
        ITaxable(peak).setTaxCollectorAddress(_taxCollectorAddress);
    }

    function excludeAddressFromTax(address _address) external onlyOperator returns (bool) {
        return _excludeAddressFromTax(_address);
    }

    function _excludeAddressFromTax(address _address) private returns (bool) {
        if (!ITaxable(peak).isAddressExcluded(_address)) {
            return ITaxable(peak).excludeAddress(_address);
        }
    }

    function includeAddressInTax(address _address) external onlyOperator returns (bool) {
        return _includeAddressInTax(_address);
    }

    function _includeAddressInTax(address _address) private returns (bool) {
        if (ITaxable(peak).isAddressExcluded(_address)) {
            return ITaxable(peak).includeAddress(_address);
        }
    }

    function taxRate() external view returns (uint256) {
        return ITaxable(peak).taxRate();
    }

    function addLiquidityTaxFree(
        address token,
        uint256 amtPeak,
        uint256 amtToken,
        uint256 amtPeakMin,
        uint256 amtTokenMin
    )
        external
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(amtPeak != 0 && amtToken != 0, "amounts can't be 0");
        _excludeAddressFromTax(_msgSender());

        IERC20(peak).transferFrom(_msgSender(), address(this), amtPeak);
        IERC20(token).transferFrom(_msgSender(), address(this), amtToken);
        _approveTokenIfNeeded(peak, uniRouter);
        _approveTokenIfNeeded(token, uniRouter);

        _includeAddressInTax(_msgSender());

        uint256 resultAmtPeak;
        uint256 resultAmtToken;
        uint256 liquidity;
        (resultAmtPeak, resultAmtToken, liquidity) = IUniswapV2Router(uniRouter).addLiquidity(
            peak,
            token,
            amtPeak,
            amtToken,
            amtPeakMin,
            amtTokenMin,
            _msgSender(),
            block.timestamp
        );

        if(amtPeak.sub(resultAmtPeak) > 0) {
            IERC20(peak).transfer(_msgSender(), amtPeak.sub(resultAmtPeak));
        }
        if(amtToken.sub(resultAmtToken) > 0) {
            IERC20(token).transfer(_msgSender(), amtToken.sub(resultAmtToken));
        }
        return (resultAmtPeak, resultAmtToken, liquidity);
    }

    function addLiquidityMetisTaxFree(
        uint256 amtPeak,
        uint256 amtPeakMin,
        uint256 amtMetisMin
    )
        external
        payable
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(amtPeak != 0 && msg.value != 0, "amounts can't be 0");
        _excludeAddressFromTax(_msgSender());

        IERC20(peak).transferFrom(_msgSender(), address(this), amtPeak);
        _approveTokenIfNeeded(peak, uniRouter);

        _includeAddressInTax(_msgSender());

        uint256 resultAmtPeak;
        uint256 resultAmtMetis;
        uint256 liquidity;
        (resultAmtPeak, resultAmtMetis, liquidity) = IUniswapV2Router(uniRouter).addLiquidityMetis{value: msg.value}(
            peak,
            amtPeak,
            amtPeakMin,
            amtMetisMin,
            _msgSender(),
            block.timestamp
        );

        if(amtPeak.sub(resultAmtPeak) > 0) {
            IERC20(peak).transfer(_msgSender(), amtPeak.sub(resultAmtPeak));
        }
        return (resultAmtPeak, resultAmtMetis, liquidity);
    }

    function setTaxablePeakOracle(address _peakOracle) external onlyOperator {
        ITaxable(peak).setPeakOracle(_peakOracle);
    }

    function transferTaxOffice(address _newTaxOffice) external onlyOperator {
        ITaxable(peak).setTaxOffice(_newTaxOffice);
    }

    function taxFreeTransferFrom(
        address _sender,
        address _recipient,
        uint256 _amt
    ) external {
        require(taxExclusionEnabled[_msgSender()], "Address not approved for tax free transfers");
        _excludeAddressFromTax(_sender);
        IERC20(peak).transferFrom(_sender, _recipient, _amt);
        _includeAddressInTax(_sender);
    }

    function setTaxExclusionForAddress(address _address, bool _excluded) external onlyOperator {
        taxExclusionEnabled[_address] = _excluded;
    }

    function _approveTokenIfNeeded(address _token, address _router) private {
        if (IERC20(_token).allowance(address(this), _router) == 0) {
            IERC20(_token).approve(_router, type(uint256).max);
        }
    }
}
