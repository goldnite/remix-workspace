// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

// HELGToken with Governance.
contract Bunny is ERC20("Bunny", "BUNNY"), Ownable {
    using SafeMath for uint256;

    uint256 private constant _maxTotalSupply = 1000000e18; // 1,000,000 max supply

    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) public onlyOwner {
        require(
            totalSupply().add(_amount) <= _maxTotalSupply,
            "ERC20: minting more than MaxTotalSupply"
        );

        _mint(_to, _amount);
    }

    // Returns maximum total supply of the token
    function getMaxTotalSupply() external pure returns (uint256) {
        return _maxTotalSupply;
    }
}
