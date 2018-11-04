import os
import logging
def get_logger(lvl = os.environ.get("LOG_LEVEL"), name=None):
    if lvl is None:
        lvl = 'INFO'
    lvl_map = {'INFO': logging.INFO, 'WARNING': logging.WARNING, 'DEBUG': logging.DEBUG}
    if lvl not in lvl_map:
        raise RuntimeError("LOG_LEVEL was " + str(lvl) + " should be one of " +
                           ", ".join(list(lvl_map.keys())))
    lvl = lvl_map[lvl]
    if name is None:
        logger = logging.getLogger()
    else:
        logger = logging.getLogger(name)
    logger.setLevel(lvl)
    ch = logging.StreamHandler()
    formatter = logging.Formatter('%(levelname) -10s %(asctime)s %(module)s:%(lineno)s %(funcName)s - %(message)s')
    ch.setLevel(lvl)
    ch.setFormatter(formatter)
    logger.handlers = [ch]
    return logger