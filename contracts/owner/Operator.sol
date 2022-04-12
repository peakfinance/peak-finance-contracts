// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Operator is ContextUpgradeable, OwnableUpgradeable {
    address private _operator;

    event OperatorTransferred(address indexed previousOperator, address indexed newOperator);

    function __Operator_init() internal onlyInitializing {
        __Context_init_unchained();
        __Operator_init_unchained();
    }

    function __Operator_init_unchained() internal onlyInitializing {
        _transferOwnership(_msgSender());
    }

    function operator() public view returns (address) {
        return _operator;
    }

    modifier onlyOperator() {
        require(_operator == _msgSender(), "operator: caller is not the operator");
        _;
    }

    function isOperator() public view returns (bool) {
        return _msgSender() == _operator;
    }

    function transferOperator(address newOperator_) public onlyOwner {
        _transferOperator(newOperator_);
    }

    function _transferOperator(address newOperator_) internal {
        require(newOperator_ != address(0), "operator: zero address given for new operator");
        emit OperatorTransferred(address(0), newOperator_);
        _operator = newOperator_;
    }
    uint256[49] private __gap;
}
