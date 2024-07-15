pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

contract TBANFT is IERC721Enumerable, ERC721 {

    uint256 public nextTokenId = 1;
    string public baseURI;
    string public contractURI;
    address public admin;
    mapping(address => bool) public minter;

    // Mapping from owner to list of owned token IDs
    mapping(address => mapping(uint256 => uint256)) private _ownedTokens;

    // Mapping from token ID to index of the owner tokens list
    mapping(uint256 => uint256) private _ownedTokensIndex;

    // Array with all token ids, used for enumeration
    uint256[] private _allTokens;

    // Mapping from token id to position in the allTokens array
    mapping(uint256 => uint256) private _allTokensIndex;

    constructor(string memory name_, string memory symbol_, string memory baseURI_, string memory contractURI_) ERC721(name_, symbol_) {
        baseURI = baseURI_;
        contractURI = contractURI_;
        minter[msg.sender] = true;
        admin = msg.sender;
    }

    function changeAdmin(address newAdmin_) public {
        require(admin == msg.sender, 'Invalid admin!');
        admin = newAdmin_;
    }

    function setMinter(address minter_, bool mint_) public {
        require(admin == msg.sender, 'Invalid admin!');
        minter[minter_] = mint_;
    }

    function mint(address owner_) public returns(uint256){
        require(minter[msg.sender], 'Invalid minter!');
        return _mint(owner_);
    }

    function airdrop(address[] calldata owners_) public {
        require(minter[msg.sender], 'Invalid minter!');
        for(uint256 i=0;i<owners_.length;i++){
            _mint(owners_[i]);
        }
    }

    function setBaseURI(string memory baseURI_) public{
        require(admin == msg.sender, 'Invalid admin!');
        baseURI = baseURI_;
    }

    function setContractURI(string memory contractURI_) public{
        require(admin == msg.sender, 'Invalid admin!');
        contractURI = contractURI_;
    }

    function _mint(address owner_) internal returns(uint256){
        uint256 tokenId = nextTokenId;
        _safeMint(owner_, tokenId);
        nextTokenId++;
        return tokenId;
    }

    function tokenOfOwnerByIndex(address owner, uint256 index) public view virtual returns (uint256) {
        require(index < balanceOf(owner), "ERC721Enumerable: owner index out of bounds!");
        return _ownedTokens[owner][index];
    }

    function tokenByIndex(uint256 index) public view virtual returns (uint256) {
        require(index < nextTokenId, "ERC721Enumerable: global index out of bounds!");
        return _allTokens[index];
    }

    function totalSupply() external view returns (uint256) {
        return _allTokens.length;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721,IERC165) returns (bool) {
        return interfaceId == type(IERC721Enumerable).interfaceId || super.supportsInterface(interfaceId);
    }

    function _baseURI() internal view override virtual returns (string memory){
        return baseURI;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId);

        if (from == address(0)) {
            _addTokenToAllTokensEnumeration(tokenId);
        } else if (from != to) {
            _removeTokenFromOwnerEnumeration(from, tokenId);
        }
        if (to == address(0)) {
            _removeTokenFromAllTokensEnumeration(tokenId);
        } else if (to != from) {
            _addTokenToOwnerEnumeration(to, tokenId);
        }
    }

    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        uint256 length = balanceOf(to);
        _ownedTokens[to][length] = tokenId;
        _ownedTokensIndex[tokenId] = length;
    }

    function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
        _allTokensIndex[tokenId] = _allTokens.length;
        _allTokens.push(tokenId);
    }

    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = balanceOf(from) - 1;
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];

            _ownedTokens[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _ownedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete _ownedTokensIndex[tokenId];
        delete _ownedTokens[from][lastTokenIndex];
    }

    function _removeTokenFromAllTokensEnumeration(uint256 tokenId) private {
        // To prevent a gap in the tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = _allTokens.length - 1;
        uint256 tokenIndex = _allTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary. However, since this occurs so
        // rarely (when the last minted token is burnt) that we still do the swap here to avoid the gas cost of adding
        // an 'if' statement (like in _removeTokenFromOwnerEnumeration)
        uint256 lastTokenId = _allTokens[lastTokenIndex];

        _allTokens[tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
        _allTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index

        delete _allTokensIndex[tokenId];
        _allTokens.pop();
    }
}
