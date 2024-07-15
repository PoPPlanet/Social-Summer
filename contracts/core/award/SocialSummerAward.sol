// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC6551Account} from '../../interfaces/IERC6551Account.sol';

contract SocialSummerAward is EIP712Upgradeable {

    address public summerNight;
    address public verifyAddress;
    address public governance;
    //erc20 => id => amount
    mapping(address => mapping(uint256 => uint256)) private ids;
    //erc20 => claimedTotalAmount
    mapping(address => uint256) public claimedTotalAmount;
    //tba => erc20 => claimedTotalAmount
    mapping(address => mapping(address => uint256)) public tbaClaimedTotalAmount;


    bytes32 private constant TYPEHASH =
    keccak256(
        "VerifyRequest(uint256 id,uint256 validityStartTimestamp,uint256 validityEndTimestamp,uint256 amount,address receiptTbaAddress,address erc20Address)"
    );

    struct VerifyRequest {
        uint256 id;
        uint256 validityStartTimestamp;
        uint256 validityEndTimestamp;
        uint256 amount;
        address payable receiptTbaAddress;
        address erc20Address;
    }

    event Claimed(
        address msgSender,
        address receiptTbaAddress,
        address receiptAddress,
        uint256 id,
        uint256 amount,
        address erc20Address
    );

    constructor (address _verifyAddress, address _summerNight) initializer {
        __EIP712_init('ClaimTokenWithSignature', "1");
        verifyAddress = _verifyAddress;
        summerNight = _summerNight;
        governance = msg.sender;
    }

    function changeGovernance(address _newGovernance) public {
        require(msg.sender == governance, 'Not governance');
        governance = _newGovernance;
    }

    function changeVerifyAddress(address _newVerifyAddress) public {
        require(msg.sender == governance, 'Not governance');
        verifyAddress = _newVerifyAddress;
    }

    function claimToSummerNight(address erc20, uint256 amount) public {
        require(msg.sender == governance, 'Not governance');
        IERC20(erc20).transfer(summerNight, amount);
    }

    function claim(VerifyRequest calldata _req, bytes calldata _signature) public {
        require(ids[_req.erc20Address][_req.id] == 0, "Invalid id");
        require(verifyRequest(_req, _signature), "Invalid signature");
        (, address tokenContract, uint256 tokenId) = IERC6551Account(_req.receiptTbaAddress).token();
        address nftOwner = IERC721(tokenContract).ownerOf(tokenId);
        require(nftOwner != address(0), 'NFT owner is address 0.');
        if (_req.erc20Address == address(0)){
            payable(nftOwner).transfer(_req.amount);
        } else {
            IERC20(_req.erc20Address).transfer(nftOwner, _req.amount);
        }
        ids[_req.erc20Address][_req.id] = _req.amount;
        claimedTotalAmount[_req.erc20Address] += _req.amount;
        tbaClaimedTotalAmount[_req.receiptTbaAddress][_req.erc20Address] += _req.amount;
        emit Claimed(msg.sender, _req.receiptTbaAddress, nftOwner, _req.id, _req.amount, _req.erc20Address);
    }

    function checkId(address _erc20Address, uint256 _id) public view returns(uint256) {
        return ids[_erc20Address][_id];
    }

    function verifyRequest(VerifyRequest calldata _req, bytes calldata _signature) public view returns (bool) {
        require(_req.validityStartTimestamp <= block.timestamp && _req.validityEndTimestamp >= block.timestamp, "request expired");
        address signer = recoverAddress(_req, _signature);
        return signer == verifyAddress;
    }

    function recoverAddress(VerifyRequest calldata _req, bytes calldata _signature) private view returns (address) {
        return ECDSAUpgradeable.recover(_hashTypedDataV4(keccak256(_encodeRequest(_req))), _signature);
    }

    function _encodeRequest(VerifyRequest calldata _req) private pure returns (bytes memory) {
        return
        abi.encode(
            TYPEHASH,
            _req.id,
            _req.validityStartTimestamp,
            _req.validityEndTimestamp,
            _req.amount,
            _req.receiptTbaAddress,
            _req.erc20Address
        );
    }

    receive() external payable {}
}
