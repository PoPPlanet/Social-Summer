pragma solidity ^0.8.0;

interface IEchoNFT {
    function setTokenIdTokenUri(uint256 profileId, uint256 pubId, string calldata contentURI) external returns (uint256);
    function mint(address to, uint256 id, uint256 amount) external;
}
