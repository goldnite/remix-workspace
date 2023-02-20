// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./Hedera/HederaTokenService.sol";
import "./Hedera/IHederaTokenService.sol";
import "./Hedera/HederaResponseCodes.sol";
import "./Hedera/ExpiryHelper.sol";
import "./Hedera/FeeHelper.sol";
import "./Hedera/KeyHelper.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// @title HLEG Fungible Token
// @author GoldenDev91
// @dev The functions implemented make use of Hedera Token Service precompiled contract
contract HLEG is HederaTokenService, Ownable, ExpiryHelper, KeyHelper {
    string private constant _name = "HLEG";
    string private constant _symbol = "HLEG";
    string private constant _memo = "This is $HLEG token";
    int64 private _maxSupply = 1e18; // 100M
    uint32 private _decimals = 10;
    uint32 private constant _autoRenewPeriod = 7776000; //90 days

    uint256 _initialized = 0;

    // @dev The address of the fungible token
    address public tokenAddress;

    // NFT Stake
    address public nftAddress =
        address(0x000000000000000000000000000000000002ed618c);  //HL_TOKEN_ID

    uint256 public performanceFee = 1e9; // 10 Hbar

    uint256 public totalStaked = 0;
    uint256 public sm = 10;
    uint256 public md = 30;
    uint256 public lg = 60;
    uint256 public smReward = 100 * 10**10;
    uint256 public mdReward = 300 * 10**10;
    uint256 public lgReward = 600 * 10**10;

    struct StakeInfo {
        address owner;
        uint256 period;
        uint256 timestamp;
    }

    StakeInfo[] public vault;
    mapping(address => uint256[]) stakeByOwners;

    event NFTStaked(
        address owner,
        int64[] serialNumbers,
        uint256 timestamp,
        uint256 totalStaked
    );
    event NFTUnstaked(
        address owner,
        int64[] serialNumbers,
        uint256 timestamp,
        uint256 totalStaked
    );
    event Claimed(address owner, uint256 amount, uint256 timestamp);

    error StakeError(uint256 errorCode);
    error UnstakeError(uint256 errorCode);

    modifier isValidPeriod(uint256 period) {
        require(period == sm || period == md || period == lg, "Wrong period");
        _;
    }

    // @notice Error used when reverting the minting function if it doesn't receive the required payment amount
    error InsufficientPay();

    // @dev Error used to revert if an error occurred during HTS mint
    error MintError(uint256 errorCode);

    // @dev Error used to revert if an error occurred during HTS transfer
    error TransferError(uint256 errorCode);

    // @dev event used if a mint was successful
    event TokenMint(
        address indexed tokenAddress,
        uint256 amount,
        uint256 newSupply
    );

    // @dev event used after tokens have been transferred
    event TokenTransfer(
        address indexed tokenAddress,
        address indexed from,
        address indexed to,
        uint256 amount
    );

    // @dev Modifier to test if while minting, the necessary amount of hbars is paid
    modifier isPaymentCovered() {
        if (performanceFee > msg.value && msg.sender != owner()) {
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

    constructor() {
        // NFT Stake
        (
            int256 response,
            IHederaTokenService.TokenInfo memory nftInfo
        ) = HederaTokenService.getTokenInfo(nftAddress);
        require(response == HederaResponseCodes.SUCCESS, "NFT not set");
        for (int64 i = 0; i <= nftInfo.token.maxSupply; i++) {
            StakeInfo memory stakeInfo;
            vault.push(stakeInfo);
        }
        require(
            vault.length == uint256(uint64(nftInfo.token.maxSupply)) + 1,
            "Initializing failed"
        );
        require(
            HederaTokenService.associateToken(address(this), nftAddress) ==
                HederaResponseCodes.SUCCESS,
            "Association failed"
        );
    }

    // @dev Initializer - Create an fungible token and returns its address
    function initialize()
        public
        payable
        onlyOwner
        initializer
        returns (uint256 respCode, address tokenAddr)
    {
        IHederaTokenService.TokenKey[]
            memory keys = new IHederaTokenService.TokenKey[](1);
        // Set this contract as supply
        keys[0] = getSingleKey(
            KeyType.SUPPLY,
            KeyValueType.CONTRACT_ID,
            address(this)
        );

        IHederaTokenService.HederaToken memory token;
        token.name = _name;
        token.symbol = _symbol;
        token.treasury = address(this);
        token.memo = _memo;
        token.tokenSupplyType = true; // set supply to FINITE
        token.maxSupply = _maxSupply;
        token.freezeDefault = false;
        token.tokenKeys = keys;
        token.expiry = createAutoRenewExpiry(address(this), _autoRenewPeriod); // Contract automatically renew by himself

        (int256 responseCode, address createdToken) = HederaTokenService
            .createFungibleToken(token, 0, _decimals);

        if (responseCode != HederaResponseCodes.SUCCESS) {
            revert("Failed to create fungible token");
        }

        tokenAddress = createdToken;
        _initialized = block.timestamp;

        return (uint256(responseCode), tokenAddress);
    }

    // NFT Stake
    function stake(int64[] calldata serialNumbers, uint256 _stakingPeriod)
        external
        payable
        isPaymentCovered
        isValidPeriod(_stakingPeriod)
    {
        uint256 serialNumber;
        for (uint256 i = 0; i < serialNumbers.length; i++) {
            serialNumber = uint256(int256(serialNumbers[i]));
            require(vault[serialNumber].period == 0, "already staked");
            require(
                IERC721(nftAddress).ownerOf(serialNumber) == msg.sender,
                "Not your token"
            );
            vault[serialNumber] = StakeInfo({
                owner: msg.sender,
                period: _stakingPeriod,
                timestamp: block.timestamp
            });
            stakeByOwners[msg.sender].push(serialNumber);
        }
        address[] memory ownerArray = _generateAddressArray(
            msg.sender,
            serialNumbers.length
        );
        address[] memory thisArray = _generateAddressArray(
            address(this),
            serialNumbers.length
        );
        int256 response = HederaTokenService.transferNFTs(
            nftAddress,
            ownerArray,
            thisArray,
            serialNumbers
        );
        if (response != HederaResponseCodes.SUCCESS) {
            revert StakeError(uint256(response));
        }
        totalStaked += serialNumbers.length;
        emit NFTStaked(msg.sender, serialNumbers, block.timestamp, totalStaked);
    }

    function unstake(int64[] calldata serialNumbers)
        external
        payable
        isPaymentCovered
        returns (uint256 claimedValue)
    {
        uint256 serialNumber;
        claimedValue = 0;
        for (uint256 i = 0; i < serialNumbers.length; i++) {
            serialNumber = uint256(int256(serialNumbers[i]));
            require(vault[serialNumber].period > 0, "Not staked");
            require(vault[serialNumber].owner == msg.sender, "Not your token");
            if (
                vault[serialNumber].timestamp +
                    86400 *
                    vault[serialNumber].period <=
                block.timestamp
            ) {
                claimedValue += _calcReward(serialNumber);
            }
            vault[serialNumber] = StakeInfo({
                owner: address(0),
                period: 0,
                timestamp: 0
            });
            uint256[] storage senderStake = stakeByOwners[msg.sender];
            uint256 len = senderStake.length;
            for (uint256 j = 0; j < len; j++) {
                if (senderStake[j] == serialNumber) {
                    senderStake[j] = senderStake[len - 1];
                    senderStake.pop();
                    break;
                }
            }
        }
        address[] memory ownerArray = _generateAddressArray(
            msg.sender,
            serialNumbers.length
        );
        address[] memory thisArray = _generateAddressArray(
            address(this),
            serialNumbers.length
        );
        int256 response = HederaTokenService.transferNFTs(
            nftAddress,
            thisArray,
            ownerArray,
            serialNumbers
        );

        if (response != HederaResponseCodes.SUCCESS) {
            revert TransferError(uint256(response));
        }
        totalStaked -= serialNumbers.length;

        emit NFTUnstaked(
            msg.sender,
            serialNumbers,
            block.timestamp,
            totalStaked
        );

        if (claimedValue > 0) {
            mintTo(msg.sender, claimedValue);
            emit Claimed(msg.sender, claimedValue, block.timestamp);
        }
    }

    function _calcReward(uint256 serialNumber)
        internal
        view
        returns (uint256 reward)
    {
        // uint256 end = vault[serialNumber].timestamp +
        //     86400 *
        //     vault[serialNumber].period;
        // if (end > block.timestamp) end = block.timestamp;
        if (vault[serialNumber].period == sm) reward = smReward;
        if (vault[serialNumber].period == md) reward = mdReward;
        if (vault[serialNumber].period == lg) reward = lgReward;
        // reward =
        //     (reward * (end - vault[serialNumber].timestamp)) /
        //     vault[serialNumber].period /
        //     86400;
    }

    function withdraw() external onlyOwner afterInitialize returns (uint256) {
        uint256 balance = address(this).balance;
        (bool os, ) = payable(owner()).call{value: address(this).balance}("");
        require(os, "withdraw failed");
        return balance;
    }

    function myStake()
        external
        view
        afterInitialize
        returns (StakeInfo[] memory infos)
    {
        uint256[] storage senderStake = stakeByOwners[msg.sender];
        uint256 len = senderStake.length;
        infos = new StakeInfo[](len);
        for (uint256 i = 0; i < len; i++) {
            infos[i] = vault[senderStake[i]];
            infos[i].owner = address(uint160(senderStake[i])); // Send serial number instead of owner
        }
    }

    // @dev mint - Mint tokens and transfer to receiver, only callable by Owner
    function mint(address receiver, uint256 amount)
        public
        afterInitialize
        onlyOwner
        returns (int256, int256)
    {
        return (_mint(amount), _transfer(receiver, amount));
    }

    // @dev internal mintTo - Mint tokens and transfer to receiver, only callable by this contract
    function mintTo(address receiver, uint256 amount)
        internal
        afterInitialize
        returns (int256, int256)
    {
        return (_mint(amount), _transfer(receiver, amount));
    }

    // @dev internal mint - Mint tokens, the minted tokens will be owned by contract
    function _mint(uint256 amount) internal returns (int256) {
        (int256 response, uint64 newSupply, ) = HederaTokenService.mintToken(
            tokenAddress,
            uint64(amount),
            new bytes[](0)
        );

        if (response != HederaResponseCodes.SUCCESS) {
            revert MintError(uint256(response));
        }
        emit TokenMint(tokenAddress, amount, newSupply);
        return response;
    }

    // Contract setting functions

    function setSmall(uint256 period, uint256 reward)
        external
        onlyOwner
        afterInitialize
    {
        sm = period;
        smReward = reward;
    }

    function setMedium(uint256 period, uint256 reward)
        external
        onlyOwner
        afterInitialize
    {
        md = period;
        mdReward = reward;
    }

    function setLarge(uint256 period, uint256 reward)
        external
        onlyOwner
        afterInitialize
    {
        lg = period;
        lgReward = reward;
    }

    // @dev internal transfer - Transfer NFTs of contract into receiver
    function _transfer(address receiver, uint256 amount)
        internal
        returns (int256)
    {
        // HederaTokenService.associateToken(receiver, tokenAddress);
        int256 response = HederaTokenService.transferToken(
            tokenAddress,
            address(this),
            receiver,
            int64(int256(amount))
        );
        if (response != HederaResponseCodes.SUCCESS) {
            revert TransferError(uint256(response));
        }
        emit TokenTransfer(tokenAddress, address(this), receiver, amount);
        return response;
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

    // ERC20 Interfaces

    function name() public view returns (string memory) {
        return IERC20Metadata(tokenAddress).name();
    }

    function symbol() public view returns (string memory) {
        return IERC20Metadata(tokenAddress).symbol();
    }

    function decimals() public view returns (uint256) {
        return IERC20Metadata(tokenAddress).decimals();
    }

    function totalSupply() public view returns (uint256) {
        return IERC20(tokenAddress).totalSupply();
    }

    function balanceOf(address account) public view returns (uint256) {
        return IERC20(tokenAddress).balanceOf(account);
    }

    /*
    function transfer(address recipient, uint256 amount) public returns(bool){
        return IERC20(tokenAddress).transfer(recipient, amount);
    }

    function delegateTransfer(address recipient, uint256 amount) public {
        (bool success, bytes memory result) = address(IERC20(tokenAddress))
            .delegatecall(
                abi.encodeWithSignature(
                    "transfer(address,uint256)",
                    recipient,
                    amount
                )
            );0
        return result;
    }

    function allowance(address owner, address spender)
        external
        view
        returns (uint256)
    {
        return IERC20(tokenAddress).allowance(owner, spender);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        return IERC20(tokenAddress).approve(spender, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        return IERC20(tokenAddress).transferFrom(sender, recipient, amount);
    }
    */
}
