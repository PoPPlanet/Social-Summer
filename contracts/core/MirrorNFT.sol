// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IPoPPHub} from '../interfaces/IPoPPHub.sol';
import {Errors} from '../libraries/Errors.sol';
import {IMirrorNFT} from "../interfaces/IMirrorNFT.sol";
import {ProfileTokenURILogic} from '../libraries/ProfileTokenURILogic.sol';
import '@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol';
import '@openzeppelin/contracts/utils/Base64.sol';
import '@openzeppelin/contracts/utils/Strings.sol';

/**
 * @title FollowNFT
 * @author PoPP Protocol
 *
 * @notice This contract is the NFT that is minted upon following a given profile. It is cloned upon first follow for a
 * given profile, and includes built-in governance power and delegation mechanisms.
 *
 * NOTE: This contract assumes total NFT supply for this follow NFT will never exceed 2^128 - 1
 */
contract MirrorNFT is ERC1155Supply,IMirrorNFT {

    uint256 internal _tokenIdCounter = 0;

    mapping(uint256 => string) private contentURIMap;

    address public immutable HUB;

    string public name = 'PoPP Echo Mirror';

    string public symbol = 'PEM';

    //tokenId => profileId => mirrorPubId
    mapping(uint256 => mapping(uint256 => uint256)) public tokenIdProfileIdPubId;
    //profileId => mirrorPubId => tokenId
    mapping(uint256 => mapping(uint256 => uint256)) public profileIdPubIdTokenId;

    //tokenId => profileId
    mapping(uint256 => uint256) public profileIdMap;

    constructor(address hub) ERC1155(''){
        if (hub == address(0)) revert Errors.InitParamsInvalid();
        HUB = hub;
    }

    function mint(address to, uint256 profileId, uint256 pubId, string calldata contentURI) external returns(uint256) {
        if (msg.sender != HUB) revert Errors.NotHub();
        uint256 tokenId = profileIdPubIdTokenId[profileId][pubId];
        if (tokenId == 0) {
            tokenId = ++_tokenIdCounter;
            profileIdPubIdTokenId[profileId][pubId] = tokenId;
        }
        super._mint(to, tokenId, 1, '0x');
        contentURIMap[tokenId] = contentURI;
        tokenIdProfileIdPubId[tokenId][profileId] = pubId;
        profileIdMap[tokenId] = pubId;
        return tokenId;
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        uint256 _profileId = profileIdMap[tokenId];
        if (_profileId == 0) {
            revert Errors.TokenDoesNotExist();
        }
        string memory handle = IPoPPHub(HUB).getHandle(_profileId);
        string memory tokenIdWithSymbol = string(abi.encodePacked('Mirror#', Strings.toString(tokenId)));
        return
        string(
            abi.encodePacked(
                'data:application/json;base64,',
                Base64.encode(
                    abi.encodePacked(
                        '{"name":"PoPP Echo Mirror","description":"Proof that mirror ',
                        handle,
                        '\'s Echo","image":"',
                        ProfileTokenURILogic.getSVGImageBase64Encoded(tokenIdWithSymbol, 'https://storage.popp.club/profile/ForwardingContractCover.png'),
                        '"}'
                    )
                )
            )
        );
    }

    function contentURI(uint256 tokenId) public view returns (string memory) {
        return contentURIMap[tokenId];
    }

}
