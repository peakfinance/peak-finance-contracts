// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./owner/Operator.sol";

contract PShareSwapper is Operator {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    IERC20Upgradeable public peak;
    IERC20Upgradeable public pbond;
    IERC20Upgradeable public pshare;

    address public peakNetSwapLpPair;
    address public pshareNetSwapLpPair;

    address public wmetisAddress;

    address public daoAddress;

    event PBondSwapPerformed(address indexed sender, uint256 pbondAmount, uint256 pshareAmount);

    function initialize(
        address _peak,
        address _pbond,
        address _pshare,
        address _wmetisAddress,
        address _peakNetSwapLpPair,
        address _pshareNetSwapLpPair,
        address _daoAddress
    ) public initializer {
        __Operator_init_unchained();
        __PShareSwapper_init_unchained(
            _peak,
            _pbond,
            _pshare,
            _wmetisAddress,
            _peakNetSwapLpPair,
            _pshareNetSwapLpPair,
            _daoAddress
        );
    }

    function __PShareSwapper_init_unchained(
        address _peak,
        address _pbond,
        address _pshare,
        address _wmetisAddress,
        address _peakNetSwapLpPair,
        address _pshareNetSwapLpPair,
        address _daoAddress
    ) internal onlyInitializing {
        peak = IERC20Upgradeable(_peak);
        pbond = IERC20Upgradeable(_pbond);
        pshare = IERC20Upgradeable(_pshare);
        wmetisAddress = _wmetisAddress;
        peakNetSwapLpPair = _peakNetSwapLpPair;
        pshareNetSwapLpPair = _pshareNetSwapLpPair;
        daoAddress = _daoAddress;
    }

    modifier isSwappable() {
        //TODO: What is a good number here?
        require(peak.totalSupply() >= 60 ether, "ChipSwapMechanismV2.isSwappable(): Insufficient supply.");
        _;
    }

    function estimateAmountOfPShare(uint256 _pbondAmount) external view returns (uint256) {
        uint256 pshareAmountPerPeak = getPShareAmountPerPeak();
        return _pbondAmount.mul(pshareAmountPerPeak).div(1e18);
    }

    function swapPBondToPShare(uint256 _pbondAmount) external {
        require(getPBondBalance(_msgSender()) >= _pbondAmount, "Not enough PBond in wallet");

        uint256 pshareAmountPerPeak = getPShareAmountPerPeak();
        uint256 pshareAmount = _pbondAmount.mul(pshareAmountPerPeak).div(1e18);
        require(getPShareBalance() >= pshareAmount, "Not enough PShare.");

        pbond.safeTransferFrom(_msgSender(), daoAddress, _pbondAmount);
        pshare.safeTransfer(_msgSender(), pshareAmount);

        emit PBondSwapPerformed(_msgSender(), _pbondAmount, pshareAmount);
    }

    function withdrawPShare(uint256 _amount) external onlyOperator {
        require(getPShareBalance() >= _amount, "ChipSwapMechanism.withdrawFish(): Insufficient FISH balance.");
        pshare.safeTransfer(_msgSender(), _amount);
    }

    function getPShareBalance() public view returns (uint256) {
        return pshare.balanceOf(address(this));
    }

    function getPBondBalance(address _user) public view returns (uint256) {
        return pbond.balanceOf(_user);
    }

    function getPeakPrice() public view returns (uint256) {
        return IERC20Upgradeable(wmetisAddress).balanceOf(peakNetSwapLpPair)
            .mul(1e18)
	    .div(peak.balanceOf(peakNetSwapLpPair));
    }

    function getPSharePrice() public view returns (uint256) {
        return IERC20Upgradeable(wmetisAddress).balanceOf(pshareNetSwapLpPair)
            .mul(1e18)
            .div(pshare.balanceOf(pshareNetSwapLpPair));
    }

    function getPShareAmountPerPeak() public view returns (uint256) {
        uint256 peakPrice = IERC20Upgradeable(wmetisAddress).balanceOf(peakNetSwapLpPair)
            .mul(1e18)
	    .div(peak.balanceOf(peakNetSwapLpPair));

        uint256 psharePrice =
            IERC20Upgradeable(wmetisAddress).balanceOf(pshareNetSwapLpPair)
	    .mul(1e18)
            .div(pshare.balanceOf(pshareNetSwapLpPair));
            

        return peakPrice.mul(1e18).div(psharePrice);
    }

}