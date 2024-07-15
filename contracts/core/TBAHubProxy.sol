// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IPoPPHub} from '../interfaces/IPoPPHub.sol';
import {IFollowNFT} from '../interfaces/IFollowNFT.sol';
import {Events} from '../libraries/Events.sol';
import {Helpers} from '../libraries/Helpers.sol';
import {Constants} from '../libraries/Constants.sol';
import {DataTypes} from '../libraries/DataTypes.sol';
import {Errors} from '../libraries/Errors.sol';
import {PublishingLogic} from '../libraries/PublishingLogic.sol';
import {ProfileTokenURILogic} from '../libraries/ProfileTokenURILogic.sol';
import {InteractionLogic} from '../libraries/InteractionLogic.sol';
import {PoPPMultiState} from './base/PoPPMultiState.sol';
import {PoPPHubStorage} from './storage/PoPPHubStorage.sol';
import {VersionedInitializable} from '../upgradeability/VersionedInitializable.sol';
import {IERC721Enumerable} from '@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol';
import {IERC6551Registry} from '../interfaces/IERC6551Registry.sol';
import {IERC6551Account} from '../interfaces/IERC6551Account.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IEchoNFT} from '../interfaces/IEchoNFT.sol';
import {IMirrorNFT} from "../interfaces/IMirrorNFT.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title PoPPHub
 * @author PoPP Protocol
 *
 * @notice This is the main entrypoint of the PoPP Protocol. It contains governance functionality as well as
 * publishing and profile interaction functionality.
 *
 * NOTE: The PoPP Protocol is unique in that frontend operators need to track a potentially overwhelming
 * number of NFT contracts and interactions at once. For that reason, we've made two quirky design decisions:
 *      1. Both Follow NFTs invoke an PoPPHub callback on transfer with the sole purpose of emitting an event.
 *      2. Almost every event in the protocol emits the current block timestamp, reducing the need to fetch it manually.
 */
contract TBAHubProxy is VersionedInitializable, PoPPMultiState, PoPPHubStorage, IPoPPHub {
    uint256 internal constant REVISION = 1;

    address internal immutable FOLLOW_NFT_IMPL;
    address internal immutable ERC6551_ACCOUNT_IMPL;
    address internal immutable ERC6551_REGISTRY;
    address internal immutable ECHO_NFT_ADDRESS;
    address internal immutable MIRROR_NFT_ADDRESS;
    address public immutable USDT_ADDRESS;
    address public immutable TBA_NFT_ADDRESS;
    bytes32 internal ERC6551_SALT = '0x000000000000000000000000000';

    /**
     * @dev This modifier reverts if the caller is not the configured governance address.
     */
    modifier onlyGov() {
        _validateCallerIsGovernance();
        _;
    }

    /**
     * @dev The constructor sets the immutable follow NFT implementations.
     *
     * @param followNFTImpl The follow NFT implementation address.
     */
    constructor(address followNFTImpl
                , address erc6551AccountImpl
                , address erc6551Registry
                , address echoNFTAddress
                , address mirrorNFTAddress
                , address usdtAddress
                , address tbaNFTAddress
    ) {
        FOLLOW_NFT_IMPL = followNFTImpl;
        ERC6551_ACCOUNT_IMPL = erc6551AccountImpl;
        ERC6551_REGISTRY = erc6551Registry;
        ECHO_NFT_ADDRESS = echoNFTAddress;
        MIRROR_NFT_ADDRESS = mirrorNFTAddress;
        USDT_ADDRESS = usdtAddress;
        TBA_NFT_ADDRESS = tbaNFTAddress;
    }

    /// @inheritdoc IPoPPHub
    function initialize(
        address newGovernance, address teamAddress, address _summerAwardAddress, address _summerAwardNightAddress
    ) external override initializer {
        _setState(DataTypes.ProtocolState.Paused);
        _setGovernance(newGovernance);
        newUserPrice = 0.003 ether;
        systemPrice = 0.006 ether;
        proxyCreator[_governance] = true;
        teamAwardAddress = teamAddress;
        summerAwardAddress = _summerAwardAddress;
        summerAwardNightAddress = _summerAwardNightAddress;
    }

    /// ***********************
    /// *****GOV FUNCTIONS*****
    /// ***********************

    /// @inheritdoc IPoPPHub
    function setGovernance(address newGovernance) external override onlyGov {
        _setGovernance(newGovernance);
    }

    function setTeamAwardAddress(address newTeamAwardAddress) external onlyGov {
        teamAwardAddress = newTeamAwardAddress;
    }

    function setProxyCreator(address _proxyCreator, bool create) external onlyGov {
        proxyCreator[_proxyCreator] = create;
    }

    function setNewUserPrice(uint256 _newUserPrice) public onlyGov {
        newUserPrice = _newUserPrice;
    }

    function setSystemPrice(uint256 newSystemPrice) public onlyGov {
        systemPrice = newSystemPrice;
    }

    /// @inheritdoc IPoPPHub
    function setEmergencyAdmin(address newEmergencyAdmin) external override onlyGov {
        address prevEmergencyAdmin = _emergencyAdmin;
        _emergencyAdmin = newEmergencyAdmin;
        emit Events.EmergencyAdminSet(
            msg.sender,
            prevEmergencyAdmin,
            newEmergencyAdmin,
            block.timestamp
        );
    }

    /// @inheritdoc IPoPPHub
    function setState(DataTypes.ProtocolState newState) external override {
        if (msg.sender == _emergencyAdmin) {
            if (newState == DataTypes.ProtocolState.Unpaused)
                revert Errors.EmergencyAdminCannotUnpause();
            _validateNotPaused();
        } else if (msg.sender != _governance) {
            revert Errors.NotGovernanceOrEmergencyAdmin();
        }
        _setState(newState);
    }

    /// @inheritdoc IPoPPHub
    function whitelistFollowModule(address followModule, bool whitelist) external override onlyGov {
        _followModuleWhitelisted[followModule] = whitelist;
        emit Events.FollowModuleWhitelisted(followModule, whitelist, block.timestamp);
    }

    /// @inheritdoc IPoPPHub
    function whitelistReferenceModule(address referenceModule, bool whitelist)
    external
    override
    onlyGov
    {
        _referenceModuleWhitelisted[referenceModule] = whitelist;
        emit Events.ReferenceModuleWhitelisted(referenceModule, whitelist, block.timestamp);
    }

    /// *********************************
    /// *****PROFILE OWNER FUNCTIONS*****
    /// *********************************

    function batchCreateAccount(DataTypes.CreateProfileData[] calldata vars)
    external
    whenNotPaused payable
    {
        uint256 price = getPrice(msg.sender);
        uint256 amount = price*vars.length;
        require(msg.value == amount, 'Invalid msg.value');
//        require(IERC20(USDT_ADDRESS).transferFrom(msg.sender, teamAwardAddress, amount*TEAM/BASE), 'Pay fail.');
        payable(teamAwardAddress).transfer(amount*TEAM/BASE);
//        require(IERC20(USDT_ADDRESS).transferFrom(msg.sender, summerAwardAddress, amount*OTHER/BASE), 'Pay fail.');
        payable(summerAwardAddress).transfer(amount*OTHER/BASE);
//        require(IERC20(USDT_ADDRESS).transferFrom(msg.sender, summerAwardNightAddress, amount*NIGHT/BASE), 'Pay fail.');
        payable(summerAwardNightAddress).transfer(amount*NIGHT/BASE);
        for(uint i=0;i<vars.length;i++){
            _createProfile(vars[i], price);
        }
        oldUser[msg.sender] = true;
    }

    function createAccount(DataTypes.CreateProfileData calldata vars)
    external
    override
    whenNotPaused payable
    returns (uint256)
    {
        uint256 price = getPrice(msg.sender);
        require(msg.value == price, 'Invalid msg.value');
//        require(IERC20(USDT_ADDRESS).transferFrom(msg.sender, teamAwardAddress, price*TEAM/BASE), 'Pay fail.');
        payable(teamAwardAddress).transfer(price*TEAM/BASE);
//        require(IERC20(USDT_ADDRESS).transferFrom(msg.sender, summerAwardAddress, price*OTHER/BASE), 'Pay fail.');
        payable(summerAwardAddress).transfer(price*OTHER/BASE);
//        require(IERC20(USDT_ADDRESS).transferFrom(msg.sender, summerAwardNightAddress, price*NIGHT/BASE), 'Pay fail.');
        payable(summerAwardNightAddress).transfer(price*NIGHT/BASE);
        uint256 profileId = _createProfile(vars, price);
        oldUser[msg.sender] = true;
        return profileId;
    }

    function proxyCreateAccount(DataTypes.CreateProfileData[] calldata vars)
    external
    whenNotPaused payable
    {
        uint256 price = getPrice(vars[0].nftOwner);
        uint256 amount = price*vars.length;
        require(msg.value>=amount, 'Invalid msg.value');
        require(proxyCreator[msg.sender], 'Not governance');
        payable(teamAwardAddress).transfer(amount*TEAM/BASE);
        payable(summerAwardAddress).transfer(amount*OTHER/BASE);
        payable(summerAwardNightAddress).transfer(amount*NIGHT/BASE);

        for(uint i=0;i<vars.length;i++){
            _createProfile(vars[i], price);
            oldUser[vars[i].nftOwner] = true;
        }
    }

    function luck(uint256 level, uint256 round, uint256 times, uint256 start, uint256 end) external {
        require(level>=1 && level<=3 && times>=1, "Invalid level.");
        require(luckNumberRecord[round][level][times].luckNumber==0, "Invalid params.");
        if (level<3){
            require(times==1, "Invalid times.");
        }
        require(msg.sender == _governance, "Only the governance can call this function");
        uint256 MAX_RANGE = end - start + 1;
        uint256 luckNumber = uint256(
            keccak256(abi.encodePacked(msg.sender, block.timestamp, blockhash(block.number - 1), level, round, times))
        ) % MAX_RANGE + start;

        DataTypes.LuckNumberRecord memory ln;
        ln.round = round;
        ln.level = level;
        ln.times = times;
        ln.start = start;
        ln.end = end;
        ln.luckNumber = luckNumber;
        luckNumberRecord[round][level][times] = ln;
        emit Events.LuckNumber(level, round, times, start, end, luckNumber);
    }

    function luckBlack(uint256 round, uint256 start, uint256 end) external {
        require(msg.sender == _governance, "Only the governance can call this function");
        require(luckBlackNumberRecord[round].luckNumber==0, "Invalid params.");

        uint256 randomNumber = uint256(
            keccak256(abi.encodePacked(msg.sender, block.timestamp, block.difficulty, blockhash(block.number - 1 + round)))
        ) % 100;

        if (randomNumber < 10) {
            uint256 MAX_RANGE = end - start + 1;

            uint256 luckNumber = uint256(
                keccak256(abi.encodePacked(msg.sender, block.timestamp, blockhash(block.number - 1 + round)))
            ) % MAX_RANGE + start;

            emit Events.LuckBlack(round, start, end, luckNumber);
            DataTypes.LuckNumberRecord memory ln;
            ln.round = round;
            ln.level = 0;
            ln.times = 0;
            ln.start = start;
            ln.end = end;
            ln.luckNumber = luckNumber;
            luckBlackNumberRecord[round] = ln;
        } else {
            emit Events.LuckBlack(round, start, end, 0);
        }
    }

    function _createProfile(DataTypes.CreateProfileData calldata vars, uint256 price) internal returns (uint256) {
        DataTypes.TBANFTInfo memory tbaInfo;
        tbaInfo.originTokenId = vars.tokenId;
        tbaInfo.originChainId = vars.chainId;
        tbaInfo.originTokenAddress = vars.tokenAddress;
        require(vars.nftOwner != address(0), 'NFT owner is address0.');
        if (vars.chainId != block.chainid || vars.tokenAddress == address(0)){
            uint256 tempTokenId = IFollowNFT(TBA_NFT_ADDRESS).mint(vars.nftOwner);
            if (vars.tokenAddress == address(0)){
                tbaInfo.originTokenId = tempTokenId;
                tbaInfo.originChainId = block.chainid;
                tbaInfo.originTokenAddress = TBA_NFT_ADDRESS;
            }
            tbaInfo.tokenId = tempTokenId;
            tbaInfo.chainId = block.chainid;
            tbaInfo.tokenAddress = TBA_NFT_ADDRESS;
        } else {
            tbaInfo.tokenId = vars.tokenId;
            tbaInfo.chainId = vars.chainId;
            tbaInfo.tokenAddress = vars.tokenAddress;
        }
    unchecked {
        uint256 profileId = ++_profileCounter;
        string memory handle = string(abi.encodePacked('profile#', Strings.toString(profileId)));
        address payable tba = IERC6551Registry(ERC6551_REGISTRY).createAccount(ERC6551_ACCOUNT_IMPL, ERC6551_SALT, block.chainid, tbaInfo.tokenAddress, tbaInfo.tokenId);
        PublishingLogic.createProfile(
            vars,
            profileId,
            handle,
            _profileIdByHandleHash,
            _profileById,
            _followModuleWhitelisted
        );
        _profileById[profileId].tbaAddress = tba;
        tbaNftInfo[profileId] = tbaInfo;
        nftProfileMap[tbaInfo.originChainId][tbaInfo.originTokenAddress][tbaInfo.originTokenId] = profileId;
        if (vars.chainId != block.chainid){
            nftProfileMap[tbaInfo.chainId][tbaInfo.tokenAddress][tbaInfo.tokenId] = profileId;
        }
        emit Events.CreateAccount(vars.nftOwner, tba, price, ERC6551_ACCOUNT_IMPL, vars.inviter, vars.chainId, vars.tokenAddress, vars.tokenId, profileId);
        autoFollow(profileId, vars.inviter);
        return profileId;
    }
    }

    function autoFollow(uint256 followerProfileId, address payable inviterTabAddress) internal {
        if (inviterTabAddress == address(0)){
            return;
        }
        address erc6551Account = _getERC6551Account(followerProfileId);
        (uint256 chainId, address tokenContract, uint256 tokenId) = IERC6551Account(inviterTabAddress).token();
        uint256 profileId = nftProfileMap[chainId][tokenContract][tokenId];
        bytes memory data = toBytesNickJohnson(followerProfileId);
        InteractionLogic.follow(
            ownerOf(followerProfileId),
            erc6551Account,
            profileId,
            data,
            _profileById,
            _profileIdByHandleHash
        );
    }

    function toBytesNickJohnson(uint256 x) public pure returns (bytes memory b) {
        b = new bytes(32);
        assembly { mstore(add(b, 32), x) }
    }

    /// @inheritdoc IPoPPHub
    function setFollowModule(
        uint256 profileId,
        address followModule,
        bytes calldata followModuleInitData
    ) external override whenNotPaused {
        _validateCallerIsProfileOwner(profileId);
        PublishingLogic.setFollowModule(
            profileId,
            followModule,
            followModuleInitData,
            _profileById[profileId],
            _followModuleWhitelisted
        );
    }

    /// @inheritdoc IPoPPHub
    function setProfileImageURI(uint256 profileId, string calldata imageURI)
    external
    override
    whenNotPaused
    {
        _validateCallerIsProfileOwnerOrDispatcher(profileId);
        _setProfileImageURI(profileId, imageURI);
    }

    /// @inheritdoc IPoPPHub
    function setProfileHandle(uint256 profileId, string calldata handle)
    external
    override
    whenNotPaused
    {
        string memory handleTemp = handle;
        PublishingLogic.validateHandle(handleTemp);
        bytes32 handleHash = keccak256(bytes(handle));
        if (_profileIdByHandleHash[handleHash] != 0) revert Errors.HandleTaken();
        _validateCallerIsProfileOwnerOrDispatcher(profileId);
        _profileById[profileId].handle = handle;
        emit Events.ProfileHandleSet(profileId, handle, block.timestamp);
    }

    /// @inheritdoc IPoPPHub
    function setFollowNFTURI(uint256 profileId, string calldata followNFTURI)
    external
    override
    whenNotPaused
    {
        _validateCallerIsProfileOwnerOrDispatcher(profileId);
        _setFollowNFTURI(profileId, followNFTURI);
    }

    /// @inheritdoc IPoPPHub
    function post(DataTypes.PostData calldata vars)
    external
    override
    whenPublishingEnabled
    returns (uint256)
    {
        _validateCallerIsProfileOwnerOrDispatcher(vars.profileId);
        return
        _createPost(
            vars.profileId,
            vars.contentURI,
            vars.financeModule,
            vars.referenceModule,
            vars.referenceModuleInitData
        );
    }

    /// @inheritdoc IPoPPHub
    function mirror(DataTypes.MirrorData calldata vars)
    external
    override
    whenPublishingEnabled
    returns (uint256)
    {
        _validateCallerIsProfileOwnerOrDispatcher(vars.profileId);
        return _createMirror(vars);
    }

    /// ***************************************
    /// *****PROFILE INTERACTION FUNCTIONS*****
    /// ***************************************

    /// @inheritdoc IPoPPHub
    function follow(uint256 followerProfileId, uint256 profileId, bytes calldata data)
    external
    override
    whenNotPaused
    returns (uint256)
    {
        _validateCallerIsProfileOwnerOrDispatcher(followerProfileId);
        address erc6551Account = _getERC6551Account(followerProfileId);
        return
        InteractionLogic.follow(
            msg.sender,
            erc6551Account,
            profileId,
            data,
            _profileById,
            _profileIdByHandleHash
        );
    }

    /// @inheritdoc IPoPPHub
    function emitFollowNFTTransferEvent(
        uint256 profileId,
        uint256 followNFTId,
        address from,
        address to
    ) external override {
        address expectedFollowNFT = _profileById[profileId].followNFT;
        if (msg.sender != expectedFollowNFT) revert Errors.CallerNotFollowNFT();
        emit Events.FollowNFTTransferred(profileId, followNFTId, from, to, block.timestamp);
    }

    /// *********************************
    /// *****EXTERNAL VIEW FUNCTIONS*****
    /// *********************************

    /// @inheritdoc IPoPPHub
    function isFollowModuleWhitelisted(address followModule) external view override returns (bool) {
        return _followModuleWhitelisted[followModule];
    }

    /// @inheritdoc IPoPPHub
    function isReferenceModuleWhitelisted(address referenceModule)
    external
    view
    override
    returns (bool)
    {
        return _referenceModuleWhitelisted[referenceModule];
    }

    /// @inheritdoc IPoPPHub
    function getGovernance() external view override returns (address) {
        return _governance;
    }

    /// @inheritdoc IPoPPHub
    function getPubCount(uint256 profileId) external view override returns (uint256) {
        return _profileById[profileId].pubCount;
    }

    /// @inheritdoc IPoPPHub
    function getFollowNFT(uint256 profileId) external view override returns (address) {
        return _profileById[profileId].followNFT;
    }

    /// @inheritdoc IPoPPHub
    function getFollowNFTURI(uint256 profileId) external view override returns (string memory) {
        return _profileById[profileId].followNFTURI;
    }

    function getMirrorNFT(uint256 profileId, uint256 pubId)
    external
    view
    override
    returns (uint256)
    {
        return _pubByIdByProfile[profileId][pubId].mirrorId;
    }

    /// @inheritdoc IPoPPHub
    function getFollowModule(uint256 profileId) external view override returns (address) {
        return _profileById[profileId].followModule;
    }

    /// @inheritdoc IPoPPHub
    function getReferenceModule(uint256 profileId, uint256 pubId)
    external
    view
    override
    returns (address)
    {
        return _pubByIdByProfile[profileId][pubId].referenceModule;
    }

    /// @inheritdoc IPoPPHub
    function getHandle(uint256 profileId) external view override returns (string memory) {
        return _profileById[profileId].handle;
    }

    /// @inheritdoc IPoPPHub
    function getPubPointer(uint256 profileId, uint256 pubId)
    external
    view
    override
    returns (uint256, uint256)
    {
        uint256 profileIdPointed = _pubByIdByProfile[profileId][pubId].profileIdPointed;
        uint256 pubIdPointed = _pubByIdByProfile[profileId][pubId].pubIdPointed;
        return (profileIdPointed, pubIdPointed);
    }

    /// @inheritdoc IPoPPHub
    function getContentURI(uint256 profileId, uint256 pubId)
    external
    view
    override
    returns (string memory)
    {
        (uint256 rootProfileId, uint256 rootPubId) = Helpers.getPointedIfMirror(
            profileId,
            pubId,
            _pubByIdByProfile
        );
        return _pubByIdByProfile[rootProfileId][rootPubId].contentURI;
    }

    /// @inheritdoc IPoPPHub
    function getProfileIdByHandle(string calldata handle) external view override returns (uint256) {
        bytes32 handleHash = keccak256(bytes(handle));
        return _profileIdByHandleHash[handleHash];
    }

    /// @inheritdoc IPoPPHub
    function getProfile(uint256 profileId)
    external
    view
    override
    returns (DataTypes.ProfileStruct memory)
    {
        return _profileById[profileId];
    }

    /// @inheritdoc IPoPPHub
    function getPub(uint256 profileId, uint256 pubId)
    external
    view
    override
    returns (DataTypes.PublicationStruct memory)
    {
        return _pubByIdByProfile[profileId][pubId];
    }

    /// @inheritdoc IPoPPHub
    function getPubType(uint256 profileId, uint256 pubId)
    external
    view
    override
    returns (DataTypes.PubType)
    {
        if (pubId == 0 || _profileById[profileId].pubCount < pubId) {
            return DataTypes.PubType.Nonexistent;
        } else if (_pubByIdByProfile[profileId][pubId].profileIdPointed>0 && (_pubByIdByProfile[profileId][pubId].profileIdPointed != profileId || _pubByIdByProfile[profileId][pubId].pubIdPointed == pubId)) {
            return DataTypes.PubType.Mirror;
        } else if (_pubByIdByProfile[profileId][pubId].profileIdPointed == 0) {
            return DataTypes.PubType.Post;
        } else {
            return DataTypes.PubType.Comment;
        }
    }

    /**
     * @dev Overrides the ERC721 tokenURI function to return the associated URI with a given profile.
     */
    function tokenURI(uint256 tokenId) public view returns (string memory) {
        address followNFT = _profileById[tokenId].followNFT;
        return
        ProfileTokenURILogic.getProfileTokenURI(
            tokenId,
            followNFT == address(0) ? 0 : IERC721Enumerable(followNFT).totalSupply(),
            ownerOf(tokenId),
            _profileById[tokenId].handle,
            _profileById[tokenId].imageURI
        );
    }

    function imageURI(uint256 tokenId) public view override returns (string memory) {
        return _profileById[tokenId].imageURI;
    }

    /// @inheritdoc IPoPPHub
    function getFollowNFTImpl() external view override returns (address) {
        return FOLLOW_NFT_IMPL;
    }

    /// @inheritdoc IPoPPHub
    function getEchoNFTImpl() external view override returns (address) {
        return ECHO_NFT_ADDRESS;
    }

    function getMirrorNFTImpl() external view override returns (address) {
        return MIRROR_NFT_ADDRESS;
    }

    /// @inheritdoc IPoPPHub
    function getERC6551Account(uint256 profileId) external view returns (address){
        return _getERC6551Account(profileId);
    }

    function _getERC6551Account(uint256 profileId) internal view returns (address){
        return _profileById[profileId].tbaAddress;
    }

    function _isFollowing(uint256 followerProfileId, uint256 followedProfileId) internal view returns (bool) {
        address followNFT = _profileById[followedProfileId].followNFT;
        if (followNFT == address(0)){
            return false;
        }
        address erc6551Account = _getERC6551Account(followerProfileId);
        return IERC721(followNFT).balanceOf(erc6551Account) > 0;
    }

    /// ****************************
    /// *****INTERNAL FUNCTIONS*****
    /// ****************************

    function _setGovernance(address newGovernance) internal {
        address prevGovernance = _governance;
        _governance = newGovernance;
        emit Events.GovernanceSet(msg.sender, prevGovernance, newGovernance, block.timestamp);
    }

    function _createPost(
        uint256 profileId,
        string memory contentURI,
        address financeModule,
        address referenceModule,
        bytes memory referenceModuleData
    ) internal returns (uint256) {
    unchecked {
        uint256 pubId = ++_profileById[profileId].pubCount;
        if (!_financeModuleWhitelisted[financeModule]) revert Errors.FinanceModuleNotWhitelisted();
        PublishingLogic.createPost(
            profileId,
            contentURI,
            referenceModule,
            referenceModuleData,
            pubId,
            _pubByIdByProfile,
            _referenceModuleWhitelisted
        );
        uint256 echoId = IEchoNFT(ECHO_NFT_ADDRESS).setTokenIdTokenUri(profileId, pubId, contentURI);
        _pubByIdByProfile[profileId][pubId].echoId = echoId;
        return pubId;
    }
    }

    function _createMirror(DataTypes.MirrorData memory vars) internal returns (uint256) {
    unchecked {
        uint256 pubId = ++_profileById[vars.profileId].pubCount;
        (uint256 rootProfileIdPointed, uint256 rootPubIdPointed) = PublishingLogic.createMirror(
            vars,
            pubId,
            _pubByIdByProfile,
            _referenceModuleWhitelisted
        );
        address erc6551Account = _getERC6551Account(vars.profileId);
        uint256 mirrorNFTTokenId = IMirrorNFT(MIRROR_NFT_ADDRESS)
            .mint(erc6551Account, rootProfileIdPointed, rootPubIdPointed, _pubByIdByProfile[rootProfileIdPointed][rootPubIdPointed].contentURI);
        if (_pubByIdByProfile[rootProfileIdPointed][rootPubIdPointed].mirrorId == 0){
            _pubByIdByProfile[rootProfileIdPointed][rootPubIdPointed].mirrorId = mirrorNFTTokenId;
        }
        if (_pubByIdByProfile[vars.profileIdPointed][vars.pubIdPointed].mirrorId == 0) {
            _pubByIdByProfile[vars.profileIdPointed][vars.pubIdPointed].mirrorId = mirrorNFTTokenId;
        }
        _pubByIdByProfile[vars.profileId][pubId].mirrorId = mirrorNFTTokenId;
        return pubId;
    }
    }

    function _setProfileImageURI(uint256 profileId, string calldata imageURI) internal {
        if (bytes(imageURI).length > Constants.MAX_PROFILE_IMAGE_URI_LENGTH)
            revert Errors.ProfileImageURILengthInvalid();
        _profileById[profileId].imageURI = imageURI;
        emit Events.ProfileImageURISet(profileId, imageURI, block.timestamp);
    }

    function _setFollowNFTURI(uint256 profileId, string calldata followNFTURI) internal {
        _profileById[profileId].followNFTURI = followNFTURI;
        emit Events.FollowNFTURISet(profileId, followNFTURI, block.timestamp);
    }

    function _clearHandleHash(uint256 profileId) internal {
        bytes32 handleHash = keccak256(bytes(_profileById[profileId].handle));
        _profileIdByHandleHash[handleHash] = 0;
    }

    function _validateCallerIsProfileOwnerOrDispatcher(uint256 profileId) internal view {
        if (msg.sender == ownerOf(profileId)){
            return;
        }
        revert Errors.NotProfileOwnerOrDispatcher();
    }

    function _validateCallerIsProfileOwner(uint256 profileId) internal view {
        if (msg.sender != ownerOf(profileId)) revert Errors.NotProfileOwner();
    }

    function _validateCallerIsGovernance() internal view {
        if (msg.sender != _governance) revert Errors.NotGovernance();
    }

    function getRevision() internal pure virtual override returns (uint256) {
        return REVISION;
    }

    function getEchoNftAddress()  external view returns (address){
        return ECHO_NFT_ADDRESS;
    }

    function isFollowing(uint256 followerProfileId, uint256 followedProfileId) external view returns (bool) {
        return _isFollowing(followerProfileId, followedProfileId);
    }

    function ownerOf(uint256 profileId) public view returns(address){
        address payable tbaAddress = _profileById[profileId].tbaAddress;
        (uint256 chainId, address tokenContract, uint256 tokenId) = IERC6551Account(tbaAddress).token();
        return IERC721(tokenContract).ownerOf(tokenId);
    }

    function getPrice(address addr) public view returns(uint256){
        return oldUser[addr] ? systemPrice : newUserPrice;
    }

    function indexStart() external view returns(uint256){
        return _profileCounter;
    }

    function registeredTBA(uint256 chainId, address tokenAddress, uint256 tokenId) external view returns(address){
        uint256 profileId = nftProfileMap[chainId][tokenAddress][tokenId];
        if (profileId == 0) {
            return address(0);
        }
        return _profileById[profileId].tbaAddress;
    }
}
