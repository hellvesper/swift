#!/usr/bin/env python
#
# ==-- jobstats - support for reading the contents of stats dirs --==#
#
# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See https://swift.org/LICENSE.txt for license information
# See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
#
# ==------------------------------------------------------------------------==#
#
# This module contains subroutines for loading object-representations of one or
# more directories generated by `swiftc -stats-output-dir`.

__author__ = 'Graydon Hoare'
__email__ = 'ghoare@apple.com'
__versioninfo__ = (0, 1, 0)
__version__ = '.'.join(str(v) for v in __versioninfo__)

from .jobstats import JobStats, JobProfs, load_stats_dir, merge_all_jobstats, list_stats_dir_profiles # noqa
