// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

contract SlotCalc {
    struct StakeInfo {
        address owner;
        uint256 period;
        uint256 timestamp;
        uint256 lastClaimedAt;
    }

    uint256 public NINE = 9;
    uint256 public EIGHT = 8;
    StakeInfo[] public vault;
    mapping(address => uint256[]) stakeByOwners;

    constructor() {
        for (int64 i = 0; i < 10; i++) {
            StakeInfo memory stakeInfo;
            vault.push(stakeInfo);
        }
        for (uint256 i = 0; i < 10; i++) {
            push(i + 1);
        }
    }

    function push(uint256 val) public returns (uint256[] memory) {
        stakeByOwners[msg.sender].push(val);
        return stakeByOwners[msg.sender];
    }

    function codeLength(address addr) public view returns (uint256 length) {
        return address(0).code.length;
        // return addr.code.length;
    }

    function remove(uint256 val) public returns (uint256[] memory) {
        uint256[] storage senderStake = stakeByOwners[msg.sender];
        uint256 len = senderStake.length;
        for (uint256 i = 0; i < len; i++) {
            if (senderStake[i] == val) {
                senderStake[i] = senderStake[len - 1];
                senderStake.pop();
                break;
            }
        }
        return senderStake;
    }

    function error() public pure returns (string memory) {
        string memory str = abi.decode(
            "08c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000c57726f6e6720706572696f640000000000000000000000000000000000000000",
            (string)
        );
        return str;
    }

    function edit() public returns (StakeInfo[] memory infos) {
        infos[0] = vault[0];
        infos[1] = vault[1];
    }

    function arrLocation(
        bytes32 slot,
        bytes32 index,
        bytes32 elementSize
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(slot)); // + (index * elementSize);
    }

    function mapLocation(uint256 slot, uint256 key)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(key, slot));
    }

    function bytes32Test()
        public
        pure
        returns (
            bytes32,
            bytes32,
            bytes32
        )
    {
        address myAddress = address(
            0x000000000000000000000000000000000002ec8369
        );
        bytes32 first = keccak256(abi.encode(myAddress));
        bytes32 second = keccak256(abi.encode(myAddress, uint256(16)));
        bytes32 third = keccak256(abi.encode(second));
        return (first, second, third);
    }

    function myLocation() public pure returns (bytes32) {
        address myAddress = address(
            0x000000000000000000000000000000000002ec8369
        );
        // first find arr = g[123]
        return keccak256(abi.encode(uint256(uint160(myAddress))));
        bytes32 arrLoc = mapLocation(16, uint256(uint160(myAddress))); // g is at slot 8

        // then find arr[0]
        bytes32 itemLoc = arrLocation(arrLoc, 0x0, 0x0);
        return itemLoc;
    }
}
