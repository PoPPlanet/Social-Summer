// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {FollowNFTProxy} from '../upgradeability/FollowNFTProxy.sol';
import {Helpers} from './Helpers.sol';
import {DataTypes} from './DataTypes.sol';
import {Errors} from './Errors.sol';
import {Events} from './Events.sol';
import {Constants} from './Constants.sol';
import {IFollowNFT} from '../interfaces/IFollowNFT.sol';
import {IFollowModule} from '../interfaces/IFollowModule.sol';
import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';
import {Strings} from '@openzeppelin/contracts/utils/Strings.sol';

/**
 * @title InteractionLogic
 * @author PoPP Protocol
 *
 * @notice This is the library that contains the logic for follows & collects.

 * @dev The functions are external, so they are called from the hub via `delegateCall` under the hood.
 */
library InteractionLogic {
    using Strings for uint256;

    /**
     * @notice Follows the given profiles, executing the necessary logic and module calls before minting the follow
     * NFT(s) to the follower.
     *
     * @param follower The address executing the follow.
     * @param profileId The array of profile token IDs to follow.
     * @param followModuleData The array of follow module data parameters to pass to each profile's follow module.
     * @param _profileById A pointer to the storage mapping of profile structs by profile ID.
     * @param _profileIdByHandleHash A pointer to the storage mapping of profile IDs by handle hash.
     *
     * @return uint256 An array of integers representing the minted follow NFT token ID.
     */
    function follow(
        address follower,
        address followerErc6551Account,
        uint256 profileId,
        bytes calldata followModuleData,
        mapping(uint256 => DataTypes.ProfileStruct) storage _profileById,
        mapping(bytes32 => uint256) storage _profileIdByHandleHash
    ) external returns (uint256) {
        string memory handle = _profileById[profileId].handle;
        if (_profileIdByHandleHash[keccak256(bytes(handle))] != profileId)
            revert Errors.TokenDoesNotExist();

        address followModule = _profileById[profileId].followModule;
        address followNFT = _profileById[profileId].followNFT;

        if (followNFT == address(0)) {
            followNFT = _deployFollowNFT(profileId);
            _profileById[profileId].followNFT = followNFT;
        }

        uint256 tokenId = IFollowNFT(followNFT).mint(followerErc6551Account);

        if (followModule != address(0)) {
            IFollowModule(followModule).processFollow(
                follower,
                profileId,
                followModuleData
            );
        }
        uint256[] memory profileIds = new uint256[](1);
        profileIds[0] = profileId;
        bytes[] memory followModuleDatas = new bytes[](1);
        followModuleDatas[0] = followModuleData;
        emit Events.Followed(follower, profileIds, followModuleDatas, block.timestamp);
        return tokenId;
    }

    /**
     * @notice Deploys the given profile's Follow NFT contract.
     *
     * @param profileId The token ID of the profile which Follow NFT should be deployed.
     *
     * @return address The address of the deployed Follow NFT contract.
     */
    function _deployFollowNFT(uint256 profileId) private returns (address) {
        bytes memory functionData = abi.encodeWithSelector(
            IFollowNFT.initialize.selector,
            profileId
        );
        address followNFT = address(new FollowNFTProxy(functionData));
        emit Events.FollowNFTDeployed(profileId, followNFT, block.timestamp);

        return followNFT;
    }
}
