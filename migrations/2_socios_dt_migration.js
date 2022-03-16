const SociosDT = artifacts.require("SociosDT");

module.exports = function (deployer) {
  deployer.deploy(SociosDT,'Coin Verde', 'CV');
};
