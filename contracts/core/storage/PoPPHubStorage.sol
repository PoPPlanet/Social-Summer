// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {DataTypes} from '../../libraries/DataTypes.sol';

/**
 * @title PoPPHubStorage
 * @author PoPP Protocol
 *
 * @notice This is an abstract contract that *only* contains storage for the poppHub contract. This
 * *must* be inherited last (bar interfaces) in order to preserve the poppHub storage layout. Adding
 * storage variables should be done solely at the bottom of this contract.
 */
abstract contract PoPPHubStorage {

    mapping(address => bool) internal _followModuleWhitelisted;
    mapping(address => bool) internal _financeModuleWhitelisted;
    mapping(address => bool) internal _referenceModuleWhitelisted;

    mapping(bytes32 => uint256) internal _profileIdByHandleHash;
    mapping(uint256 => DataTypes.ProfileStruct) internal _profileById;
    mapping(uint256 => mapping(uint256 => DataTypes.PublicationStruct)) internal _pubByIdByProfile;
    mapping(address => bool) public oldUser;
    //profileId=>TBANFTInfo
    mapping(uint256 => DataTypes.TBANFTInfo) public tbaNftInfo;
    //chainId=>tokenAddress=>tokenId=>profileId
    mapping(uint256=>mapping(address=>mapping(uint256=>uint256))) public nftProfileMap;

    //round=>level=>times=>LuckNumber
    mapping(uint256=>mapping(uint256=>mapping(uint256=>DataTypes.LuckNumberRecord))) public luckNumberRecord;
    //round=>LuckNumber
    mapping(uint256=>DataTypes.LuckNumberRecord) public luckBlackNumberRecord;

    uint256 internal _profileCounter;
    address internal _governance;
    address internal _emergencyAdmin;

    uint256 public newUserPrice;
    uint256 public systemPrice;

    mapping(address=>bool) public proxyCreator;
    address public teamAwardAddress;
    address public summerAwardAddress;
    address public summerAwardNightAddress;

    uint256 public immutable BASE = 10000;
    uint256 public immutable TEAM = 4000;
    uint256 public immutable OTHER = 4000;
    uint256 public immutable NIGHT = 2000;

}
