pragma solidity ^0.8.0;

import "./IERC20.sol";

interface IWrappedMetis is IERC20 {
    function deposit() external payable returns (uint256);

    function withdraw(uint256 amount) external returns (uint256);

}

