pragma solidity ^0.8.0;

interface IMirrorNFT {
    function mint(address to, uint256 profileId, uint256 pubId, string calldata contentURI) external returns(uint256);
}
