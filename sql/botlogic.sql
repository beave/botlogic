
CREATE TABLE `browser_detect` (
  `id` int(11) unsigned NOT NULL,
  `lang` varchar(16) DEFAULT NULL,
  `is_IE` tinyint(4) DEFAULT '0',
  `hasActiveX` tinyint(4) DEFAULT '0',
  `hasFirebug` tinyint(4) DEFAULT '0',
  `hasFlash` tinyint(4) DEFAULT '0',
  `office` varchar(32) DEFAULT NULL,
  `screen_width` int(11) DEFAULT NULL,
  `screen_height` int(11) DEFAULT NULL,
  `color_depth` int(11) DEFAULT NULL,
  `window_width` int(11) DEFAULT NULL,
  `window_height` int(11) DEFAULT NULL,
  `timestamp` datetime DEFAULT CURRENT_TIMESTAMP,
  `remote_addr` varchar(130) DEFAULT NULL,
  KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `browser_plugins`
--

CREATE TABLE `browser_plugins` (
  `id` int(11) unsigned NOT NULL,
  `name` varchar(128) DEFAULT NULL,
  `plugin_filename` varchar(128) DEFAULT NULL,
  `description` varchar(256) DEFAULT NULL,
  `timestamp` datetime DEFAULT CURRENT_TIMESTAMP,
  KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `expanded_url`
--

CREATE TABLE `expanded_url` (
  `id` int(11) unsigned NOT NULL,
  `expanded_url` varchar(2014) NOT NULL,
  KEY `id` (`id`),
  KEY `expanded_url` (`expanded_url`(255))
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `ip`
--

CREATE TABLE `ip` (
  `id` int(11) NOT NULL,
  `remote_addr` varchar(130) DEFAULT NULL,
  `http_user_agent` text,
  `http_referer` text,
  `remote_ident` text,
  `found_timestamp` datetime DEFAULT CURRENT_TIMESTAMP,
  KEY `id` (`id`),
  KEY `remote_addr` (`remote_addr`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `phone`
--

CREATE TABLE `phone` (
  `id` int(11) NOT NULL,
  `phone_number` varchar(64) DEFAULT NULL,
  `timestamp` datetime DEFAULT CURRENT_TIMESTAMP,
  KEY `id` (`id`),
  KEY `phone_number` (`phone_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `queue`
--

DROP TABLE IF EXISTS `queue`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `queue` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `screen_name` varchar(20) NOT NULL,
  `timestamp` datetime DEFAULT CURRENT_TIMESTAMP,
  `scanned_flag` tinyint(4) DEFAULT '0',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=82 DEFAULT CHARSET=utf8;

--
-- Table structure for table `scanned`
--

CREATE TABLE `scanned` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `twitter_id` varchar(255) NOT NULL,
  `screen_name` varchar(20) NOT NULL,
  `type` smallint(6) NOT NULL,
  `timestamp` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `twitter_id` (`twitter_id`),
  KEY `screen_name` (`screen_name`)
) ENGINE=InnoDB AUTO_INCREMENT=2697013 DEFAULT CHARSET=utf8;

--
-- Table structure for table `twitter`
--

DROP TABLE IF EXISTS `twitter`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `twitter` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `type` int(11) NOT NULL,
  `search` varchar(255) NOT NULL,
  `found_timestamp` datetime DEFAULT CURRENT_TIMESTAMP,
  `twitter_id` varchar(255) NOT NULL,
  `screen_name` varchar(20) NOT NULL,
  `name` blob NOT NULL,
  `text` blob NOT NULL,
  `location` varchar(255) DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `friends_count` int(11) unsigned NOT NULL,
  `followers_count` int(11) unsigned NOT NULL,
  `lang` varchar(16) DEFAULT NULL,
  `time_zone` varchar(64) DEFAULT NULL,
  `source` text NOT NULL,
  `sha1` varchar(41) DEFAULT NULL,
  `score` int(11) DEFAULT NULL,
  `score_text` text,
  `tweet_id` varchar(25) NOT NULL,
  `tweet_sha1` varchar(41) NOT NULL,
  `phone_code` varchar(32) DEFAULT NULL,
  `twitter_response` varchar(512) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `type` (`type`),
  KEY `twitter_id` (`twitter_id`)
) ENGINE=InnoDB AUTO_INCREMENT=277082 DEFAULT CHARSET=utf8;

--
-- Table structure for table `types`
--

CREATE TABLE `types` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `type` varchar(255) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8;

INSERT INTO `types` VALUES (1,'Fake News'),(2,'Hate Speech'),(3,'Bot'),(4,'Detect as bot but a human');

