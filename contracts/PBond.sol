// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";

import "./owner/Operator.sol";

contract PBond is ERC20BurnableUpgradeable, Operator {
    /**
     * @notice Constructs the PEAK Bond ERC-20 contract.
     */
    // constructor() ERC20("PBOND", "PBOND") {}

    function initialize() public initializer {
        __Operator_init_unchained();
        __ERC20_init_unchained("POND", "POND");
        __ERC20Burnable_init_unchained();
        __PBond_init_unchained();
    }

    function __PBond_init_unchained() internal onlyInitializing {
    }

    /**
     * @notice Operator mints basis bonds to a recipient
     * @param recipient_ The address of recipient
     * @param amount_ The amount of basis bonds to mint to
     * @return whether the process has been done
     */
    function mint(address recipient_, uint256 amount_) public onlyOperator returns (bool) {
        uint256 balanceBefore = balanceOf(recipient_);
        _mint(recipient_, amount_);
        uint256 balanceAfter = balanceOf(recipient_);

        return balanceAfter > balanceBefore;
    }

    function burn(uint256 amount) public override {
        super.burn(amount);
    }

    function burnFrom(address account, uint256 amount) public override onlyOperator {
        super.burnFrom(account, amount);
    }
}
