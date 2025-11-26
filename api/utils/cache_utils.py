#
#  Copyright 2024 The InfiniFlow Authors. All Rights Reserved.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
import json
import logging
import xxhash
from rag.utils.redis_conn import REDIS_CONN

# Cache configuration
RETRIEVAL_CACHE_EXPIRY = 180 * 24 * 3600  # Cache expiry time in seconds (6 months = 180 days)
RETRIEVAL_CACHE_PREFIX = "retrieval_cache:"
RETRIEVAL_CACHE_MAX_SIZE = 10 * 1024 * 1024 * 1024  # Maximum cache size: 10GB in bytes
RETRIEVAL_CACHE_MAX_AGE = 90 * 24 * 3600  # Maximum cache age: 3 months (90 days) in seconds


def generate_retrieval_cache_key(question, kb_ids, doc_ids, page, size, similarity_threshold, 
                                 vector_similarity_weight, top, rerank_id, highlight, tenant_id):
    """Generate a unique cache key for retrieval query."""
    hasher = xxhash.xxh64()
    # Include all parameters that affect the retrieval result
    hasher.update(str(question).encode("utf-8"))
    hasher.update(str(sorted(kb_ids)).encode("utf-8"))
    hasher.update(str(sorted(doc_ids) if doc_ids else []).encode("utf-8"))
    hasher.update(str(page).encode("utf-8"))
    hasher.update(str(size).encode("utf-8"))
    hasher.update(str(similarity_threshold).encode("utf-8"))
    hasher.update(str(vector_similarity_weight).encode("utf-8"))
    hasher.update(str(top).encode("utf-8"))
    hasher.update(str(rerank_id).encode("utf-8"))
    hasher.update(str(highlight).encode("utf-8"))
    hasher.update(str(tenant_id).encode("utf-8"))
    return RETRIEVAL_CACHE_PREFIX + hasher.hexdigest()


def get_retrieval_cache(cache_key):
    """Get retrieval result from cache."""
    try:
        if not REDIS_CONN or not REDIS_CONN.is_alive():
            return None
        cached_data = REDIS_CONN.get(cache_key)
        if cached_data:
            return json.loads(cached_data)
    except Exception as e:
        logging.warning(f"Failed to get retrieval cache: {str(e)}")
    return None


def set_retrieval_cache(cache_key, result):
    """Set retrieval result to cache."""
    try:
        if not REDIS_CONN or not REDIS_CONN.is_alive():
            return False
        # Remove vector data before caching (already done in retrieval function)
        return REDIS_CONN.set_obj(cache_key, result, RETRIEVAL_CACHE_EXPIRY)
    except Exception as e:
        logging.warning(f"Failed to set retrieval cache: {str(e)}")
    return False


def cleanup_retrieval_cache():
    """
    Clean up retrieval cache based on:
    1. Cache size exceeds 10GB
    2. Cache age exceeds 3 months (90 days)
    """
    try:
        if not REDIS_CONN or not REDIS_CONN.is_alive():
            logging.warning("Redis connection not available for cache cleanup")
            return

        # Get all retrieval cache keys
        cache_keys = REDIS_CONN.scan_keys(f"{RETRIEVAL_CACHE_PREFIX}*")
        if not cache_keys:
            logging.info("No retrieval cache keys found for cleanup")
            return

        logging.info(f"Starting retrieval cache cleanup. Found {len(cache_keys)} cache keys")
        
        total_size = 0
        keys_to_delete = []
        keys_with_age = []  # List of (key, remaining_ttl, size) tuples
        
        # Calculate total size and collect keys that exceed age limit
        for key in cache_keys:
            ttl = REDIS_CONN.get_ttl(key)
            if ttl == -2:  # Key doesn't exist, skip
                continue
            
            # Calculate cache age: age = original_expiry - remaining_ttl
            # If TTL is -1 (no expiry, shouldn't happen), treat as very old
            if ttl == -1:
                # Key has no expiry, treat as very old and delete
                keys_to_delete.append(key)
                logging.debug(f"Marking key for deletion (no expiry): {key}")
                continue
            
            # Calculate how long the cache has been stored
            # remaining_ttl is the time left until expiry
            # age = original_expiry_time - remaining_ttl
            cache_age = RETRIEVAL_CACHE_EXPIRY - ttl if ttl > 0 else RETRIEVAL_CACHE_EXPIRY
            
            if cache_age >= RETRIEVAL_CACHE_MAX_AGE:
                keys_to_delete.append(key)
                logging.debug(f"Marking key for deletion (age limit): {key}, age: {cache_age / (24*3600):.1f} days")
            else:
                # Get memory usage for size-based cleanup
                size = REDIS_CONN.get_memory_usage(key)
                total_size += size
                keys_with_age.append((key, ttl, size))

        # Delete keys that exceed age limit
        if keys_to_delete:
            deleted_count = REDIS_CONN.delete_many(keys_to_delete)
            logging.info(f"Deleted {deleted_count} cache keys due to age limit (>= 3 months)")
        
        # Check if total size exceeds limit
        if total_size > RETRIEVAL_CACHE_MAX_SIZE:
            logging.warning(f"Cache size ({total_size / (1024**3):.2f} GB) exceeds limit ({RETRIEVAL_CACHE_MAX_SIZE / (1024**3):.2f} GB)")
            
            # Sort keys by TTL (oldest first, i.e., smallest TTL = oldest)
            keys_with_age.sort(key=lambda x: x[1] if x[1] > 0 else float('inf'))
            
            # Delete oldest keys until size is under limit
            deleted_size = 0
            keys_to_delete_size = []
            for key, ttl, size in keys_with_age:
                keys_to_delete_size.append(key)
                deleted_size += size
                if total_size - deleted_size <= RETRIEVAL_CACHE_MAX_SIZE:
                    break
            
            if keys_to_delete_size:
                deleted_count = REDIS_CONN.delete_many(keys_to_delete_size)
                logging.info(f"Deleted {deleted_count} cache keys due to size limit. "
                           f"Freed {deleted_size / (1024**3):.2f} GB")
        else:
            logging.info(f"Cache size ({total_size / (1024**3):.2f} GB) is within limit")

    except Exception as e:
        logging.exception(f"Error during retrieval cache cleanup: {str(e)}")

