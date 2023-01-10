SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `zcontracts`
--

-- --------------------------------------------------------

--
-- Table structure for table `completed_contracts`
--

CREATE TABLE `completed_contracts` (
  `steamid64` char(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `contract_uuid` char(64) COLLATE utf8mb4_unicode_ci NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `contract_progress`
--

CREATE TABLE `contract_progress` (
  `steamid64` char(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `contract_uuid` char(64) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '{}',
  `progress` int(11) NOT NULL DEFAULT '0',
  `version` tinyint(4) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `objective_progress`
--

CREATE TABLE `objective_progress` (
  `steamid64` char(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `contract_uuid` char(64) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '{}',
  `objective_id` int(11) DEFAULT NULL,
  `progress` int(11) DEFAULT '0',
  `version` tinyint(4) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `preferences`
--

CREATE TABLE `preferences` (
  `steamid64` char(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `version` tinyint(4) NOT NULL,
  `display_help_text` tinyint(1) NOT NULL DEFAULT '1',
  `use_contract_hud` tinyint(1) NOT NULL DEFAULT '1',
  `use_hint_text` int(11) NOT NULL DEFAULT '1',
  `use_sounds` int(11) NOT NULL DEFAULT '1'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `selected_contract`
--

CREATE TABLE `selected_contract` (
  `steamid64` char(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `contract_uuid` char(64) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '{}'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `completed_contracts`
--
ALTER TABLE `completed_contracts`
  ADD UNIQUE KEY `steamid64` (`steamid64`,`contract_uuid`);

--
-- Indexes for table `contract_progress`
--
ALTER TABLE `contract_progress`
  ADD UNIQUE KEY `steamid64` (`steamid64`,`contract_uuid`);

--
-- Indexes for table `objective_progress`
--
ALTER TABLE `objective_progress`
  ADD UNIQUE KEY `objective_key` (`steamid64`,`contract_uuid`,`objective_id`);

--
-- Indexes for table `preferences`
--
ALTER TABLE `preferences`
  ADD PRIMARY KEY (`steamid64`);

--
-- Indexes for table `selected_contract`
--
ALTER TABLE `selected_contract`
  ADD UNIQUE KEY `steamid64` (`steamid64`);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
