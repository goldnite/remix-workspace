// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract BunnyOG is Ownable, ERC1155Receiver {
    using SafeMath for uint256;
    IERC20 reward_token;
    IERC1155 nft;

    enum period {
        SMALL,
        MEDIUM,
        LARGE,
        XLARGE
    }

    uint256 public totalStaked;
    uint256 public smallOpt = 30;
    uint256 public mediumOpt = 60;
    uint256 public largeOpt = 90;
    uint256 public xlargeOpt = 120;
    uint256 public smallReward = 5000000000000000;
    uint256 public mediumReward = 12000000000000000;
    uint256 public largeReward = 50000000000000000;
    uint256 public xlargeReward = 60000000000000000;
    uint256 public performanceFee = 0.005 ether;
    address public feeWallet;
    bool public enableTokenID ;
    mapping(uint256 => bool) public enabledTokenIDs;
    uint256[] stakedTokens;

    struct Stake {
        uint256 tokenId;
        uint256 timestamp;
        period stakingPeriod;
        address owner;
    }

    mapping(uint256 => Stake) public vault;

    event NFTStaked(address owner, uint256 tokenId, uint256 value);
    event NFTUnstaked(address owner, uint256 tokenId, uint256 value);
    event Claimed(address owner, uint256 amount);

    constructor(
        address _reward_token,
        IERC1155 _nft,
        address _feeWallet
    ) {
        reward_token = IERC20(_reward_token);
        nft = _nft;
        feeWallet = _feeWallet;
    }

    function stake(uint256[] calldata tokenIds, period _stakingPeriod)
        external
        payable
    {
        require(msg.value >= performanceFee, "Not Enough Funds");
        payable(feeWallet).transfer(msg.value);
        uint256 tokenId;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenId = tokenIds[i];
            if (enableTokenID)
                require(enabledTokenIDs[tokenId], "Not Enabled token");
            bool flag = false;
            uint256 length = nft.tokenCountOfOwner(msg.sender);
            for (uint256 j = 0; j < length; j++) {
                if (nft.tokenIdOfOwnerByIndex(msg.sender, j) == tokenIds[i]) {
                    flag = true;
                    break;
                }
            }
            require(flag, "Not your token");
            require(vault[tokenId].tokenId == 0, "already staked");

            nft.safeTransferFrom(msg.sender, address(this), tokenId, 1, "");
            stakedTokens.push(tokenId);
            emit NFTStaked(msg.sender, tokenId, block.timestamp);

            vault[tokenId] = Stake({
                owner: msg.sender,
                tokenId: tokenId,
                timestamp: block.timestamp,
                stakingPeriod: _stakingPeriod
            });
        }
        totalStaked += tokenIds.length;
    }

    function _unstakeMany(uint256[] calldata tokenIds) external payable {
        require(msg.value >= performanceFee, "Not Enough Funds");
        payable(feeWallet).transfer(msg.value);
        uint256 tokenId;
        totalStaked -= tokenIds.length;
        uint256 earned = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenId = tokenIds[i];
            if (enableTokenID)
                require(enabledTokenIDs[tokenId], "Not Enabled token");
            Stake memory staked = vault[tokenId];
            require(staked.owner == msg.sender, "not an owner");
            if (validateStakingPeriod(staked)) {
                earned += getPeriodReward(staked.stakingPeriod) * 10**5; // multiply rewards to token decimals
            }
            delete vault[tokenId];
            emit NFTUnstaked(msg.sender, tokenId, block.timestamp);
            nft.setApprovalForAll(msg.sender, true);
            nft.safeTransferFrom(address(this), msg.sender, tokenId, 1, "");
            for (uint256 j = 0; j < stakedTokens.length; j++) {
                if (stakedTokens[j] == tokenId) {
                    remove(j);
                    break;
                }
            }
        }
        if (earned > 0) {
            if (address(reward_token) == address(0x0)) {
                payable(msg.sender).transfer(earned);
            } else reward_token.transfer(msg.sender, earned);
            emit Claimed(msg.sender, earned);
        }
    }

    function depositReward(address token, uint256 amount) external payable {
        if (token != address(0x0))
            IERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    function validateStakingPeriod(Stake memory staked)
        internal
        view
        returns (bool)
    {
        uint256 periodValue = getPeriodValue(staked.stakingPeriod);
        return block.timestamp >= (staked.timestamp + (86400 * periodValue));
        // return block.timestamp >= (staked.timestamp + 900);
    }

    function getPeriodValue(period _stPeriod) internal view returns (uint256) {
        return
            _stPeriod == period.SMALL ? smallOpt : _stPeriod == period.MEDIUM
                ? mediumOpt
                : _stPeriod == period.LARGE
                ? largeOpt
                : _stPeriod == period.XLARGE
                ? xlargeOpt
                : 0;
    }

    function getNFTStakeReward(period _stPeriod, uint256 _stakeTimestamp)
        internal
        view
        returns (uint256)
    {
        uint256 totalStakeReward = getPeriodReward(_stPeriod);
        uint256 noOfDays = (block.timestamp - _stakeTimestamp)
            .div(60)
            .div(60)
            .div(24);
        noOfDays = (noOfDays < 1) ? 1 : noOfDays;
        uint256 periodValue = getPeriodValue(_stPeriod);
        return totalStakeReward.div(periodValue).mul(noOfDays);
    }

    function getPeriodReward(period _stPeriod) internal view returns (uint256) {
        return
            _stPeriod == period.SMALL ? smallReward : _stPeriod == period.MEDIUM
                ? mediumReward
                : _stPeriod == period.LARGE
                ? largeReward
                : _stPeriod == period.XLARGE
                ? xlargeReward
                : 0;
    }

    function balanceOf(address account, uint256 id)
        public
        view
        returns (uint256)
    {
        return nft.balanceOf(account, id);
    }

    function getUserStakedTokens(address account)
        external
        view
        returns (uint256[] memory)
    {
        uint256 index = 0;
        for (uint256 i = 0; i < stakedTokens.length; i++) {
            if (vault[stakedTokens[i]].owner == account) {
                index++;
            }
        }
        uint256[] memory tokenIds = new uint256[](index);
        index = 0;
        for (uint256 i = 0; i < stakedTokens.length; i++) {
            if (vault[stakedTokens[i]].owner == account) {
                tokenIds[index] = vault[stakedTokens[i]].tokenId;
                index++;
            }
        }
        return tokenIds;
    }

    function remove(uint256 index) internal {
        if (index >= stakedTokens.length) return;

        for (uint256 i = index; i < stakedTokens.length - 1; i++) {
            stakedTokens[i] = stakedTokens[i + 1];
        }
        delete stakedTokens[stakedTokens.length - 1];
        stakedTokens.pop();
    }

    function getStuckToken(address token) external onlyOwner {
        IERC20(token).transfer(owner(), IERC20(token).balanceOf(address(this)));
    }

    function getStuckEth() external onlyOwner {
        payable(owner()).transfer(owner().balance);
    }

    function setSmallOpt(uint256 _periodOpt) external onlyOwner {
        smallOpt = _periodOpt;
    }

    function setMediumOpt(uint256 _periodOpt) external onlyOwner {
        mediumOpt = _periodOpt;
    }

    function setLargeOpt(uint256 _periodOpt) external onlyOwner {
        largeOpt = _periodOpt;
    }

    function setXlargeOpt(uint256 _periodOpt) external onlyOwner {
        xlargeOpt = _periodOpt;
    }

    function setsmallReward(uint256 _reward) external onlyOwner {
        smallReward = _reward;
    }

    function setmediumReward(uint256 _reward) external onlyOwner {
        mediumReward = _reward;
    }

    function setlargeReward(uint256 _reward) external onlyOwner {
        largeReward = _reward;
    }

    function setxlargeReward(uint256 _reward) external onlyOwner {
        xlargeReward = _reward;
    }

    function setPerformanceFee(uint256 _newFee) external onlyOwner {
        performanceFee = _newFee;
    }

    function setRewardToken(address _newToken) external onlyOwner {
        reward_token = IERC20(_newToken);
    }

    function setEnableTokenID(bool _enable) external onlyOwner {
        enableTokenID = _enable;
    }

    function addEnabledTokenIDs(uint256[] memory ids) external onlyOwner {
        for (uint256 i = 0; i < ids.length; i++) enabledTokenIDs[ids[i]] = true;
    }

    function removeEnabledTokenIDs(uint256[] memory ids) external onlyOwner {
        for (uint256 i = 0; i < ids.length; i++)
            enabledTokenIDs[ids[i]] = false;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}