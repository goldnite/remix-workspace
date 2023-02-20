// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./Hedera/HederaTokenService.sol";
import "./Hedera/IHederaTokenService.sol";
import "./Hedera/HederaResponseCodes.sol";
import "./Hedera/ExpiryHelper.sol";
import "./Hedera/FeeHelper.sol";
import "./Hedera/KeyHelper.sol";

// @title HederaLegacy Non-fungible Token
// @author GoldenDev91
// @dev The functions implemented make use of Hedera Token Service precompiled contract
contract Essentials is HederaTokenService, Ownable, ExpiryHelper, KeyHelper {
    string private constant _name = "ESSENTIALS";
    string private constant _symbol = "ESSENTIALS";
    string private constant _memo =
        "NFT";
    uint256 private _maxSupply = 111;
    uint256 public cost = 10 * 0; // 10 Hbar
    string public baseURI =
        "QmU7FNsvsN4x9J4hKU81V67vUjvK3iz7Z4aa4xJrR2i9Z6/Solana_Data_";
    string public baseExtension = ".json";
    int32 private constant _autoRenewPeriod = 7776000; //90 days
    uint256 _initialized = 0;
    // @dev The address of the Non-Fungible token
    address public tokenAddress;
    // mapping(address => uint256) gifts;
    // @notice Error used when reverting the minting function if it doesn't receive the required payment amount
    error InsufficientPay();
    // @dev Error used to revert if an error occurred during HTS mint
    error MintError(uint256 errorCode);
    // @dev Error used to revert if an error occurred during HTS transfer
    error TransferError(uint256 errorCode);
    // @dev event used if a mint was successful
    event NftMint(address indexed tokenAddress, int64[] serialNumbers);
    // @dev event used after tokens have been transferred
    event NftTransfer(
        address indexed tokenAddress,
        address indexed from,
        address indexed to,
        int64[] serialNumbers
    );
    // @dev event used after tokens have been transferred
    event GiftTransfer(
        uint256 serial,
        address indexed gifteeAddress,
        uint256 giftAmount
    );
    // @dev Modifier to test if while minting, the necessary amount of hbars is paid
    modifier isPaymentCovered(uint256 amount) {
        require(amount <= 10, "Too much amount");
        if (amount * cost > msg.value && msg.sender != owner()) {
            revert InsufficientPay();
        }
        _;
    }
    // @dev Modifier to test if not initialized
    modifier initializer() {
        require(_initialized == 0, "Already initialized");
        _;
    }
    // @dev Modifier to test if initialized
    modifier afterInitialize() {
        require(_initialized != 0, "Not initialized");
        _;
    }

    constructor() {}

    // @dev Initializer - Create an non-fungible token and returns its address
    function initialize()
        external
        payable
        onlyOwner
        initializer
        returns (uint256 respCode, address tokenAddr)
    {
        IHederaTokenService.TokenKey[]
            memory keys = new IHederaTokenService.TokenKey[](2);
        // Set this contract as supply
        keys[0] = getSingleKey(
            KeyType.SUPPLY,
            KeyValueType.CONTRACT_ID,
            address(this)
        );
        keys[1] = getSingleKey(
            KeyType.PAUSE,
            KeyValueType.CONTRACT_ID,
            address(this)
        );
        IHederaTokenService.HederaToken memory token;
        token.name = _name;
        token.symbol = _symbol;
        token.treasury = address(this);
        token.memo = _memo;
        token.tokenSupplyType = true; // set supply to FINITE
        token.maxSupply = int64(int256(_maxSupply));
        token.freezeDefault = false;
        token.tokenKeys = keys;
        token.expiry = createAutoRenewExpiry(address(this), _autoRenewPeriod); // Contract automatically renew by himself
        (int256 responseCode, address createdToken) = HederaTokenService
            .createNonFungibleToken(token);
        if (responseCode != HederaResponseCodes.SUCCESS) {
            revert("Failed to create non-fungible token");
        }
        tokenAddress = createdToken;
        _initialized = block.timestamp;
        return (uint256(responseCode), tokenAddress);
    }

    // @dev mint - Mint an NFT and transfer to msg.sender
    function mint(uint256 amount)
        external
        payable
        afterInitialize
        isPaymentCovered(amount)
        returns (int64[] memory newSerialNumber)
    {
        require(totalSupply() + amount <= _maxSupply, "Exceeds max supply");
        int64[] memory serialNumbers = _mint(amount);
        _transfer(msg.sender, serialNumbers);
        // uint256 supply = totalSupply();
        // for (uint256 i = supply; i < supply + amount; i++) {
        //     address payable gifteeAddress = payable(msg.sender);
        //     uint256 giftAmount = 0;
        //     uint256 giftee = 0;
        //     if (i > 0) {
        //         while (gifteeAddress.code.length != 0 || giftee == 0) {
        //             giftee = _randomize(i, block.timestamp, i + 1) + 1;
        //             gifteeAddress = ownerOf(giftee);
        //         }
        //         // it should fall into endless loop and may cause out of fee
        //         giftAmount = i + 1 == _maxSupply
        //             ? (address(this).balance * 10) / 100
        //             : (msg.value * 5) / 100 / amount;
        //         if (giftAmount > 0) {
        //             (bool success, ) = payable(gifteeAddress).call{
        //                 value: giftAmount
        //             }("");
        //             require(success);
        //             gifts[msg.sender] += giftAmount;
        //             emit GiftTransfer(giftee, gifteeAddress, giftAmount);
        //         }
        //     }
        // }
        return serialNumbers;
    }

    // @dev internal mint - Mint NFTs, the minted NFT will be owned by contract
    function _mint(uint256 amount) internal returns (int64[] memory) {
        bytes[] memory metadata = _generateMetadataArray(
            amount,
            baseURI,
            baseExtension,
            totalSupply()
        );
        (int256 response, , int64[] memory serialNumbers) = HederaTokenService
            .mintToken(tokenAddress, 0, metadata);
        if (response != HederaResponseCodes.SUCCESS) {
            revert MintError(uint256(response));
        }
        emit NftMint(tokenAddress, serialNumbers);
        return serialNumbers;
    }

    // @dev internal transfer - Transfer NFTs of contract into receiver
    function _transfer(address receiver, int64[] memory serialNumbers)
        internal
    {
        uint256 amount = serialNumbers.length;
        HederaTokenService.associateToken(receiver, tokenAddress);
        address[] memory tokenTreasuryArray = _generateAddressArray(
            address(this),
            amount
        );
        address[] memory minterArray = _generateAddressArray(
            msg.sender,
            amount
        );
        int256 response = HederaTokenService.transferNFTs(
            tokenAddress,
            tokenTreasuryArray,
            minterArray,
            serialNumbers
        );
        if (response != HederaResponseCodes.SUCCESS) {
            revert TransferError(uint256(response));
        }
        emit NftTransfer(
            tokenAddress,
            address(this),
            msg.sender,
            serialNumbers
        );
    }

    function _randomize(
        uint256 _mod,
        uint256 _seed,
        uint256 _salt
    ) internal view returns (uint256) {
        uint256 num = uint256(
            keccak256(
                abi.encodePacked(block.timestamp, msg.sender, _seed, _salt)
            )
        ) % _mod;
        return num;
    }

    function withdraw() external onlyOwner afterInitialize returns (uint256) {
        uint256 balance = address(this).balance;
        (bool os, ) = payable(owner()).call{value: address(this).balance}("");
        require(os);
        return balance;
    }

    // Contract setting functions
    function setCost(uint256 _newCost) external onlyOwner afterInitialize {
        cost = _newCost;
    }

    function pause(bool _state)
        external
        onlyOwner
        afterInitialize
        returns (uint256 respCode)
    {
        int256 response;
        if (_state == true) {
            response = pauseToken(tokenAddress);
        } else {
            response = unpauseToken(tokenAddress);
        }
        return uint256(response);
    }

    // @dev Helper function which generates array of addresses required for HTSPrecompiled
    function _generateAddressArray(address _address, uint256 amount)
        internal
        pure
        returns (address[] memory _addresses)
    {
        _addresses = new address[](amount);
        for (uint256 i = 0; i < amount; i++) {
            _addresses[i] = _address;
        }
    }

    // @dev Helper function which generates array required for metadata by HTSPrecompiled
    function _generateMetadataArray(
        uint256 amount,
        string memory prefix,
        string memory suffix,
        uint256 startIndex
    ) internal pure returns (bytes[] memory _bytesArray) {
        _bytesArray = new bytes[](amount);
        for (uint256 i = 0; i < amount; i++) {
            string memory newSN = Strings.toString(startIndex + i + 1);
            _bytesArray[i] = bytes.concat(
                bytes(prefix),
                bytes(newSN),
                bytes(suffix)
            );
        }
    }

    // ERC721 Interfaces
    function name() public view returns (string memory) {
        return IERC721Metadata(tokenAddress).name();
    }

    function symbol() public view returns (string memory) {
        return IERC721Metadata(tokenAddress).symbol();
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        return IERC721Metadata(tokenAddress).tokenURI(tokenId);
    }

    function totalSupply() public view returns (uint256) {
        return IERC721Enumerable(tokenAddress).totalSupply();
    }

    function balanceOf(address owner) public view returns (uint256) {
        return IERC721(tokenAddress).balanceOf(owner);
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        return IERC721(tokenAddress).ownerOf(tokenId);
    }
    /*
    function approve(address _approved, uint256 _tokenId) external payable {
        IERC721(tokenAddress).approve(_approved, _tokenId);
    }
    function setApprovalForAll(address _operator, bool _approved) external {
        IERC721(tokenAddress).setApprovalForAll(_operator, _approved);
    }
    function getApproved(uint256 _tokenId) external view returns (address) {
        return IERC721(tokenAddress).getApproved(_tokenId);
    }
    function isApprovedForAll(address _owner, address _operator)
        external
        view
        returns (bool)
    {
        return IERC721(tokenAddress).isApprovedForAll(_owner, _operator);
    }
    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external payable {
        IERC721(tokenAddress).transferFrom(_from, _to, _tokenId);
    }
    */
}
