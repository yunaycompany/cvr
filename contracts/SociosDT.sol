// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract SociosDT is ERC1155Supply,  Ownable {
    using Counters for Counters.Counter;
    using SafeMath for uint256;

    string sdtName;
    string sdtSymbol;

    struct TreeData{
        uint256 limit;
        uint256 sold;
        bool locked;
    }
    struct Tree {
        string treeId;
        string farmName;
        string treeName;
        uint256 birthTime;
        string geoHash;
        uint256 amountEarnedPerFruits;
        uint256 carbonDioxideOffset;
    }


    //Is sale Open
    bool private saleOpen;
    //Is redeem allowed
    bool private redeemAllowed;
    //Purchase price
    uint256 public mintPrice = 16000000000000000;
    // Carbon Credit Fee
    uint256 private carbonCreditFee;
    //Current stage
    uint256 private currentStage;
    //  re-entrancy check
    bool internal locked;


    // Mapping from address to carbon credit
    mapping(address => uint256) public credits;
    // Mapping from address to token index to last snap time
    mapping(address => mapping(uint256 => uint256)) public lastSnap;
    // Mapping from address to token index to stage
    mapping(address => mapping(uint256 => uint256)) public lastStage;

    Counters.Counter sdtCounter;
    mapping(uint256 => Tree) public sdtTrees;
    mapping(uint256 => TreeData) public sdtTreesData;


    event Purchased(uint256 indexed _index, address indexed _account, uint256 _numOfTrees);
    event Generated(address indexed _from, uint256 indexed _tokenId, uint256 _value);
    event AmountRedeemed(address indexed _to, uint256 indexed _tokenId, uint256 _amount);
    event Redeemed(address indexed _from, uint256 _amount);

    constructor(string memory _name, string memory _symbol) ERC1155("ipfs://QmbuQ1CseLhNkgDfwXcot8z69dYFnMz7wFNDYj58Lk2RdQ/") {
        sdtName =_name;
        sdtSymbol = _symbol;
        saleOpen = false;
        redeemAllowed = false;
        currentStage = 0;
    }

    // Checks re-entrancy
    modifier noReentrant() {
        require(!locked, "No re-entrancy");
        locked = true;
        _;
        locked = false;
    }

    modifier existTree(uint256 _sdtIndex) {
        require(exists(_sdtIndex), "Token does not exist");
        _;
    }

    modifier noLocked(uint256 _sdtIndex) {
        require (!sdtTreesData[_sdtIndex].locked, "Tree Locked");
        _;
    }


    function name() public view returns (string memory) {
        return sdtName;
    }

    function symbol() public view returns (string memory) {
        return sdtSymbol;
    }


    function addTree(
        string memory _treeId,
        string memory _treeName,
        string memory _farmName,
        string memory _geoHash,
        uint256 _birthTime,
        uint256 _limit,
        uint256 _carbonDioxideOffset,
        address _to,
        uint256 _numOfTrees
    ) public onlyOwner {
        Tree storage tree = sdtTrees[sdtCounter.current()];
        tree.treeId = _treeId;
        tree.treeName = _treeName;
        tree.farmName = _farmName;
        tree.birthTime = _birthTime > 0 ? _birthTime: block.timestamp;
        tree.geoHash = _geoHash;
        tree.amountEarnedPerFruits = 0;
        tree.carbonDioxideOffset = _carbonDioxideOffset;

        TreeData storage treeData = sdtTreesData[sdtCounter.current()];
        treeData.limit = _limit;
        treeData.sold = _numOfTrees;
        treeData.locked = false;

        _mint(_to, sdtCounter.current(), _numOfTrees, "");
        sdtCounter.increment();
    }


    function mint(uint256 _sdtIndex, address _to, uint256 _numOfTrees) external onlyOwner existTree(_sdtIndex) noLocked(_sdtIndex){
        require (_numOfTrees > 0, "Invalid num of trees");
        require (sdtTreesData[_sdtIndex].sold + _numOfTrees <= sdtTreesData[_sdtIndex].limit, "Mint exceeds the allowed limit");
        _mint(_to, _sdtIndex, _numOfTrees, "");
        sdtTreesData[_sdtIndex].sold = sdtTreesData[_sdtIndex].sold + _numOfTrees;
    }

    function mintTrees(uint256 _sdtIndex, address[] calldata _to, uint256[] calldata _numOfTrees) external onlyOwner existTree(_sdtIndex) noLocked(_sdtIndex){
        require (_to.length == _numOfTrees.length, "Lengths have to match.");
        for(uint256 i = 0; i < _to.length; i++) {
            require (sdtTreesData[_sdtIndex].sold + _numOfTrees[i] <= sdtTreesData[_sdtIndex].limit, "Mint exceeds the allowed limit");
            _mint(_to[i], _sdtIndex, _numOfTrees[i], "");
            sdtTreesData[_sdtIndex].sold=sdtTreesData[_sdtIndex].sold + _numOfTrees[i];
        }
    }

    function mintBatch(address _to, uint256[] calldata _numOfTrees, uint256[] memory _sdtIndexs) external onlyOwner{
        require (_numOfTrees.length == _sdtIndexs.length, "Lengths have to match.");
        for (uint i=0; i< _sdtIndexs.length; i++) {
            uint256 sdtIndex = _sdtIndexs[i];
            require(exists(sdtIndex), "Token does not exist");
            require (!sdtTreesData[sdtIndex].locked, "Tree Locked");
            require (sdtTreesData[sdtIndex].sold + _numOfTrees[i] <= sdtTreesData[sdtIndex].limit, "Mint exceeds the allowed limit");

            sdtTreesData[sdtIndex].sold = sdtTreesData[sdtIndex].sold + _numOfTrees[i];
        }

        _mintBatch(_to, _sdtIndexs, _numOfTrees, "");
    }


    function uri(uint256 _sdtIdx) public existTree(_sdtIdx) view override returns (string memory) {
        return string(abi.encodePacked(super.uri(_sdtIdx), Strings.toString(_sdtIdx)));
    }

    function getAllTokens(address _account) external view returns(uint256[] memory){
        uint256 numOfTokens = 0;
        uint256 length = sdtCounter.current();
        for (uint i=0; i< length; i++) {
            if(balanceOf(_account, i) > 0){
                numOfTokens++;
            }
        }
        uint256 counter = 0;
        uint256[] memory tokens= new uint256[](numOfTokens);
        for (uint i=0; i< length; i++) {
            if(balanceOf(_account, i) > 0){
                tokens[counter] = i;
                counter++;
            }
        }
        return tokens;
    }

    function setURI(string memory _URI) external onlyOwner {
        _setURI(_URI);
    }

    function setSaleOpen(bool _st) external onlyOwner {
        saleOpen = _st;
    }

    function setRedeem(bool _st) external onlyOwner {
        redeemAllowed = _st;
    }

    function setAmountEarnedPerFruits(uint256 _sdtIdx, uint256 _amountEarnedPerFruits) external onlyOwner existTree(_sdtIdx){
        sdtTrees[_sdtIdx].amountEarnedPerFruits = _amountEarnedPerFruits;
    }

    function setCurrentStage() external onlyOwner{
        currentStage++;
    }

    function setLockedTree(uint256 _sdtIdx, bool _locked) external onlyOwner existTree(_sdtIdx) {
        sdtTreesData[_sdtIdx].locked = _locked;
    }

    function setMintPrice(uint256 _mP) external onlyOwner {
        mintPrice = _mP;
    }

    function setLimit(uint256 _sdtIndex, uint256 _limit) external onlyOwner existTree(_sdtIndex) {
        sdtTreesData[_sdtIndex].limit = _limit;
    }

    function setSold(uint256 _sdtIndex, uint256 _sold) external onlyOwner existTree(_sdtIndex){
        sdtTreesData[_sdtIndex].sold = _sold;
    }

    function setFarmName(uint256 _sdtIndex, string memory _farmName) external onlyOwner existTree(_sdtIndex){
        sdtTrees[_sdtIndex].farmName = _farmName;
    }

    function setTreeName(uint256 _sdtIndex, string memory _treeName) external onlyOwner existTree(_sdtIndex){
        sdtTrees[_sdtIndex].treeName = _treeName;
    }

    function setGeoHash(uint256 _sdtIndex, string memory _geoHash) external onlyOwner existTree(_sdtIndex){
        sdtTrees[_sdtIndex].geoHash = _geoHash;
    }

    function setCarbonDioxideOffset(uint256 _sdtIndex, uint256 _carbonDioxideOffset) external onlyOwner existTree(_sdtIndex){
        sdtTrees[_sdtIndex].carbonDioxideOffset = _carbonDioxideOffset;
    }

    function purchase(uint256 _numOfTrees, uint256 _sdtIdx) external payable noReentrant existTree(_sdtIdx) noLocked(_sdtIdx) {
        require(saleOpen == true, "Purchase closed");
        require (sdtTreesData[_sdtIdx].sold + _numOfTrees <= sdtTreesData[_sdtIdx].limit, "Mint exceeds the allowed limit");

        _purchase(_numOfTrees, _sdtIdx);
    }

    function _purchase(uint256 _numOfTrees, uint256 _sdtIdx) private {
        require(_numOfTrees > 0, "Purchase: invalid num of trees");
        require(msg.value >= _numOfTrees * mintPrice, "Purchase: Incorrect payment");

        _mint(msg.sender, _sdtIdx, _numOfTrees, "");
        sdtTreesData[_sdtIdx].sold = sdtTreesData[_sdtIdx].sold + _numOfTrees;
        emit Purchased(_sdtIdx, msg.sender, _numOfTrees);
    }

    function setCarbonCreditFee( uint256 _fee) external onlyOwner{
        carbonCreditFee = _fee;
    }

    function generateCarbonCredit(uint256 _tokenId) external payable noReentrant{
        uint256 balance = balanceOf(msg.sender, _tokenId);
        require(msg.value >= carbonCreditFee, "Provided value is not enough");
        require(balance > 0, "Account without tree");

        // Calculates total carbon offset until now
        uint256 total = calculateTotalCarbonCredit(_tokenId);
        credits[msg.sender] = credits[msg.sender].add(total);

        lastSnap[msg.sender][_tokenId] = block.timestamp;
        emit Generated(msg.sender, _tokenId, total);
    }

    function calculateTotalCarbonCredit(uint256 _tokenId) public view returns (uint256){
        uint256 balance = balanceOf(msg.sender, _tokenId);
        uint256 end = block.timestamp;
        uint256 start = lastSnap[msg.sender][_tokenId] > 0 ?lastSnap[msg.sender][_tokenId] : sdtTrees[_tokenId].birthTime;
        uint256 carbonDioxideOffset = balance.mul(sdtTrees[_tokenId].carbonDioxideOffset);
        return (end.sub(start)).mul(carbonDioxideOffset).div(31536000);
    }

    function redeemCarbonCredit(uint256 amount) external noReentrant{
        require(redeemAllowed, "Redeem not allowed");
        uint256 balance = credits[msg.sender] ;
        require(balance >= amount, "Invalid amount provided");

        credits[msg.sender] = credits[msg.sender].sub(amount);

        emit Redeemed(msg.sender, amount);
    }

    function redeemAmountEarnedPerFruits(uint256 _tokenId) external noReentrant{
        require(balanceOf(msg.sender, _tokenId) > 0, "Account without tree");
        require(sdtTrees[_tokenId].amountEarnedPerFruits > 0, "Invalid amount earned per fruits");
        require(lastStage[msg.sender][_tokenId] < currentStage, "Invalid stage");
        lastStage[msg.sender][_tokenId] = currentStage;
        emit AmountRedeemed(msg.sender, _tokenId,  sdtTrees[_tokenId].amountEarnedPerFruits);
    }

    function withdraw(address payable _account) external onlyOwner {
        uint256 balance = address(this).balance;
        payable(_account).transfer(balance);
    }




}
