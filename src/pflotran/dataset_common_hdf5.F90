module Dataset_Common_HDF5_class

#include "petsc/finclude/petscsys.h"
  use petscsys

  use Dataset_Base_class

  use PFLOTRAN_Constants_module

  implicit none

  private

  type, public, extends(dataset_base_type) :: dataset_common_hdf5_type
    character(len=MAXWORDLENGTH) :: hdf5_dataset_name
    PetscBool :: realization_dependent
    PetscInt :: max_buffer_size
    PetscBool :: is_cell_indexed
  end type dataset_common_hdf5_type

  public :: DatasetCommonHDF5Create, &
            DatasetCommonHDF5Init, &
            DatasetCommonHDF5Copy, &
            DatasetCommonHDF5Cast, &
            DatasetCommonHDF5Read, &
            DatasetCommonHDF5ReadSelectCase, &
            DatasetCommonHDF5Load, &
            DatasetCommonHDF5IsCellIndexed, &
            DatasetCommonHDF5GetNameInfo, &
            DatasetCommonHDF5Print, &
            DatasetCommonHDF5Strip, &
            DatasetCommonHDF5Destroy

  public :: DatasetCommonHDF5ReadTimes

contains

! ************************************************************************** !

function DatasetCommonHDF5Create()
  !
  ! Creates members of common hdf5 database class
  !
  ! Author: Glenn Hammond
  ! Date: 05/03/13
  !

  implicit none

  class(dataset_common_hdf5_type), pointer :: dataset

  class(dataset_common_hdf5_type), pointer :: DatasetCommonHDF5Create

  allocate(dataset)
  call DatasetCommonHDF5Init(dataset)

  DatasetCommonHDF5Create => dataset

end function DatasetCommonHDF5Create

! ************************************************************************** !

subroutine DatasetCommonHDF5Init(this)
  !
  ! Initializes members of common hdf5 dataset class
  !
  ! Author: Glenn Hammond
  ! Date: 05/03/13
  !

  implicit none

  class(dataset_common_hdf5_type) :: this

  call DatasetBaseInit(this)
  this%hdf5_dataset_name = ''
  this%realization_dependent = PETSC_FALSE
  this%max_buffer_size = UNINITIALIZED_INTEGER
  this%is_cell_indexed = PETSC_FALSE
  this%data_type = DATASET_REAL

end subroutine DatasetCommonHDF5Init

! ************************************************************************** !

subroutine DatasetCommonHDF5Copy(this, that)
  !
  ! Copies members of common hdf5 dataset class
  !
  ! Author: Glenn Hammond
  ! Date: 05/03/13
  !

  implicit none

  class(dataset_common_hdf5_type) :: this
  class(dataset_common_hdf5_type) :: that

  call DatasetBaseCopy(this,that)
  that%hdf5_dataset_name = this%hdf5_dataset_name
  that%realization_dependent = this%realization_dependent
  that%max_buffer_size = this%max_buffer_size
  that%is_cell_indexed = this%is_cell_indexed

end subroutine DatasetCommonHDF5Copy

! ************************************************************************** !

function DatasetCommonHDF5Cast(this)
  !
  ! Casts a dataset_base_type to dataset_common_hdf5_type
  !
  ! Author: Glenn Hammond
  ! Date: 05/03/13
  !

  implicit none

  class(dataset_base_type), pointer :: this

  class(dataset_common_hdf5_type), pointer :: DatasetCommonHDF5Cast

  nullify(DatasetCommonHDF5Cast)
  if (.not.associated(this)) return
  select type (this)
    class is (dataset_common_hdf5_type)
      DatasetCommonHDF5Cast => this
  end select

end function DatasetCommonHDF5Cast

! ************************************************************************** !

subroutine DatasetCommonHDF5Read(this,input,option)
  !
  ! Reads in contents of a dataset card
  !
  ! Author: Glenn Hammond
  ! Date: 01/12/11, 06/04/13
  !

  use Option_module
  use Input_Aux_module
  use String_module

  implicit none

  class(dataset_common_hdf5_type) :: this
  type(input_type), pointer :: input
  type(option_type) :: option

  character(len=MAXWORDLENGTH) :: keyword
  PetscBool :: found

  input%ierr = 0
  call InputPushBlock(input,option)
  do

    call InputReadPflotranString(input,option)

    if (InputCheckExit(input,option)) exit

    call InputReadCard(input,option,keyword)
    call InputErrorMsg(input,option,'keyword','DATASET')
    call StringToUpper(keyword)

    call DatasetCommonHDF5ReadSelectCase(this,input,keyword,found,option)

    if (.not.found) then
      call InputKeywordUnrecognized(input,keyword,'dataset',option)
    endif

  enddo
  call InputPopBlock(input,option)

  if (len_trim(this%hdf5_dataset_name) < 1) then
    this%hdf5_dataset_name = this%name
  endif

end subroutine DatasetCommonHDF5Read

! ************************************************************************** !

subroutine DatasetCommonHDF5ReadSelectCase(this,input,keyword,found,option)
  !
  ! Compares keyword against HDF5 common
  ! keywords
  !
  ! Author: Glenn Hammond
  ! Date: 06/04/13
  !

  use Option_module
  use Input_Aux_module
  use String_module

  implicit none

  class(dataset_common_hdf5_type) :: this
  type(input_type) :: input
  character(len=MAXWORDLENGTH) :: keyword
  PetscBool :: found
  type(option_type) :: option

  found = PETSC_TRUE
  select case(trim(keyword))
    case('NAME')
      call InputReadWord(input,option,this%name,PETSC_TRUE)
      call InputErrorMsg(input,option,'name','DATASET')
    case('HDF5_DATASET_NAME')
      call InputReadWord(input,option,this%hdf5_dataset_name,PETSC_TRUE)
      call InputErrorMsg(input,option,'hdf5_dataset_name','DATASET')
    case('FILENAME')
      call InputReadFilename(input,option,this%filename)
      call InputErrorMsg(input,option,'name','DATASET')
    case('REALIZATION_DEPENDENT')
      this%realization_dependent = PETSC_TRUE
    case('MAX_BUFFER_SIZE')
      call InputReadInt(input,option,this%max_buffer_size)
      call InputErrorMsg(input,option,'max_buffer_size','DATASET')
    case default
      found = PETSC_FALSE
  end select

end subroutine DatasetCommonHDF5ReadSelectCase

! ************************************************************************** !

subroutine DatasetCommonHDF5ReadTimes(filename,dataset_name,time_storage, &
                                      option)
  !
  ! DatasetGlobalReadTimes: Read dataset times into time storage
  !
  ! Author: Glenn Hammond
  ! Date: 01/12/08
  !

  use hdf5
  use Time_Storage_module
  use Units_module, only : UnitsConvertToInternal
  use Option_module
  use Logging_module
  use HDF5_Aux_module

  implicit none

  character(len=MAXSTRINGLENGTH) :: filename
  character(len=MAXWORDLENGTH) :: dataset_name
  type(time_storage_type), pointer :: time_storage
  type(option_type) :: option

  integer(HID_T) :: file_id
  integer(HID_T) :: file_space_id
  integer(HID_T) :: memory_space_id
  integer(HID_T) :: dataset_id
  integer(HID_T) :: prop_id
  integer(HID_T) :: grp_id
  integer(HID_T) :: atype_id
  integer(HID_T) :: attribute_id
  integer(HSIZE_T) :: num_times
  integer(HSIZE_T) :: length(1)
  integer(HSIZE_T) :: attribute_dim(1)
  integer(SIZE_T) :: size_t_int
  PetscMPIInt :: array_rank_mpi
  character(len=MAXSTRINGLENGTH) :: string
  character(len=MAXWORDLENGTH) :: attribute_name, time_units
  character(len=MAXWORDLENGTH) :: internal_units
  PetscMPIInt :: int_mpi
  PetscInt :: temp_int, num_times_read_by_iorank
  PetscMPIInt :: hdf5_err, h5fopen_err
  PetscBool :: time_attribute_exists, time_group_exists
  PetscErrorCode :: ierr

  call PetscLogEventBegin(logging%event_read_array_hdf5,ierr);CHKERRQ(ierr)

!#define TIME_READING_TIMES
#ifdef TIME_READING_TIMES
  call PetscTime(tstart,ierr);CHKERRQ(ierr)
#endif

  h5fopen_err = 0
  option%io_buffer = 'Reading times for hdf5 dataset "' // &
    trim(dataset_name) // '", if they exist.'
  call PrintMsg(option)
  if (OptionIsIORank(option)) then
    option%io_buffer = 'Opening hdf5 file: ' // trim(filename)
    call PrintMsg(option)
    ! PETSC_FALSE is because this is not collective
    call HDF5FileOpenReadOnly(filename,file_id,PETSC_FALSE,'', &
                              option,h5fopen_err)
    if (h5fopen_err == 0) then
      option%io_buffer = 'Opening hdf5 group: ' // trim(dataset_name)
      call PrintMsg(option)
      call HDF5GroupOpen(file_id,dataset_name,grp_id,option%driver)
      attribute_name = "Time Units"
      call H5aexists_f(grp_id,attribute_name,time_attribute_exists,hdf5_err)
      if (time_attribute_exists) then
        attribute_dim = 1
        call h5tcopy_f(H5T_NATIVE_CHARACTER,atype_id,hdf5_err)
        size_t_int = MAXWORDLENGTH
        call h5tset_size_f(atype_id,size_t_int,hdf5_err)
        call h5aopen_f(grp_id,attribute_name,attribute_id,hdf5_err)
        call h5aread_f(attribute_id,atype_id,time_units,attribute_dim,hdf5_err)
        call h5aclose_f(attribute_id,hdf5_err)
      else
        time_units = 's'
      endif

      ! Check whether a time array actually exists
      string = 'Times'
      call h5lexists_f(grp_id,string,time_group_exists,hdf5_err)

      if (time_group_exists) then
        if (.not.time_attribute_exists) then
          option%io_buffer = 'Time Units assumed to be seconds.'
          call PrintWrnMsg(option)
        endif
        !geh: Should check to see if "Times" dataset exists.
        option%io_buffer = 'Opening data set: ' // trim(string)
        call PrintMsg(option)
        call HDF5DatasetOpen(grp_id,string,dataset_id,option)
        call h5dget_space_f(dataset_id,file_space_id,hdf5_err)
        call h5sget_simple_extent_npoints_f(file_space_id,num_times,hdf5_err)
        num_times_read_by_iorank = int(num_times)
      else
        num_times_read_by_iorank = -1
        option%io_buffer = 'No times to read.'
        call PrintMsg(option)
        option%io_buffer = 'Closing hdf5 group: ' // trim(dataset_name)
        call PrintMsg(option)
        call HDF5GroupClose(grp_id,option)
        option%io_buffer = 'Closing hdf5 file: ' // trim(filename)
        call PrintMsg(option)
        call HDF5FileClose(file_id,option)
      endif
    endif
  endif

  ! Need to catch errors in opening the file.  Since the file is only opened
  ! by the I/O rank, need to broadcast the error flag.
  temp_int = h5fopen_err
  int_mpi = 1
  call MPI_Bcast(temp_int,int_mpi,MPI_INTEGER,option%comm%io_rank, &
                 option%mycomm,ierr);CHKERRQ(ierr)
  if (temp_int < 0) then ! actually h5fopen_err
    option%io_buffer = 'Error opening file: ' // trim(filename)
    call PrintErrMsg(option)
  endif

  int_mpi = 1
  call MPI_Bcast(num_times_read_by_iorank,int_mpi,MPI_INTEGER, &
                 option%comm%io_rank,option%mycomm,ierr);CHKERRQ(ierr)
  num_times = num_times_read_by_iorank

  if (num_times == -1) then
    ! no times exist, simply return
    return
  endif

  time_storage => TimeStorageCreate()
  time_storage%max_time_index = int(num_times)
  allocate(time_storage%times(num_times))
  time_storage%times = 0.d0

  if (OptionIsIORank(option)) then
    option%io_buffer = 'Reading times.'
    call PrintMsg(option)
    array_rank_mpi = 1
    length(1) = num_times
    call h5pcreate_f(H5P_DATASET_XFER_F,prop_id,hdf5_err)
#ifndef SERIAL_HDF5
    call h5pset_dxpl_mpio_f(prop_id,H5FD_MPIO_INDEPENDENT_F,hdf5_err)
#endif
    call h5screate_simple_f(array_rank_mpi,length,memory_space_id,hdf5_err,length)
    call h5dread_f(dataset_id,H5T_NATIVE_DOUBLE,time_storage%times, &
                    length,hdf5_err,memory_space_id,file_space_id,prop_id)


    call h5pclose_f(prop_id,hdf5_err)
    if (memory_space_id > -1) call h5sclose_f(memory_space_id,hdf5_err)
    call h5sclose_f(file_space_id,hdf5_err)
    call HDF5DatasetClose(dataset_id,option)
    option%io_buffer = 'Closing hdf5 group: ' // trim(dataset_name)
    call PrintMsg(option)
    call HDF5GroupClose(grp_id,option)
    option%io_buffer = 'Closing hdf5 file: ' // trim(filename)
    call PrintMsg(option)
    call HDF5FileClose(file_id,option)
    internal_units = 'sec'
    time_storage%times = time_storage%times * &
      UnitsConvertToInternal(time_units,internal_units, &
                             trim(dataset_name)//'Time Units',option)
  endif

  int_mpi = int(num_times)
  call MPI_Bcast(time_storage%times,int_mpi,MPI_DOUBLE_PRECISION, &
                 option%comm%io_rank,option%mycomm,ierr);CHKERRQ(ierr)

#ifdef TIME_READING_TIMES
  call MPI_Barrier(option%mycomm,ierr);CHKERRQ(ierr)
  call PetscTime(tend,ierr);CHKERRQ(ierr)
  write(option%io_buffer,'(f6.2," Seconds to read dataset times",a,".")') &
    tend-tstart, trim(dataset_name) // ' (' // trim(option%group_prefix) // &
    ')'
  if (OptionIsIORank(option)) then
    print *, trim(option%io_buffer)
  endif
#endif

  call PetscLogEventEnd(logging%event_read_array_hdf5,ierr);CHKERRQ(ierr)

end subroutine DatasetCommonHDF5ReadTimes

! ************************************************************************** !

function DatasetCommonHDF5Load(this,option)
  !
  ! Updates indices and returns whether to load new data.
  !
  ! Author: Glenn Hammond
  ! Date: 05/03/13
  !
  use Option_module
  use Time_Storage_module

  implicit none

  PetscBool :: DatasetCommonHDF5Load

  class(dataset_common_hdf5_type) :: this
  type(option_type) :: option

  PetscBool :: read_due_to_time
  PetscInt :: end_of_buffer

  DatasetCommonHDF5Load = PETSC_FALSE

  if (.not.associated(this%time_storage)) then
    call DatasetCommonHDF5ReadTimes(this%filename,this%hdf5_dataset_name, &
                                    this%time_storage,option)
    ! if no times are read, this%time_storage will be null coming out of
    ! DatasetCommonHDF5ReadTimes()
  endif

  read_due_to_time = PETSC_FALSE
  if (associated(this%time_storage)) then
    this%time_storage%cur_time = option%time
    ! sets correct cur_time_index
    call TimeStorageUpdate(this%time_storage)
    ! this > 0 conditional prevents repetitive loads of the same data
    ! during initialization
    if (this%time_storage%cur_time_index > 0) then
                      ! both of the below will be zero initially
      end_of_buffer = this%buffer_slice_offset + this%buffer_nslice
      read_due_to_time = this%time_storage%cur_time_index >= &
                         end_of_buffer .and. &
                         ! this conditional prevents repetitive loads once
                         ! max_time_index is reached
                         end_of_buffer < this%time_storage%max_time_index
    endif
  endif

  if (read_due_to_time .or. &
       ! essentially gets the data set read if only one time slice
      .not.associated(this%rarray)) then
    if (associated(this%time_storage)) then
      if (this%time_storage%cur_time_index > 0) then
        this%buffer_slice_offset = this%time_storage%cur_time_index - 1
      endif
    endif
    DatasetCommonHDF5Load = PETSC_TRUE
  endif

end function DatasetCommonHDF5Load

! ************************************************************************** !

function DatasetCommonHDF5IsCellIndexed(dataset,option)
  !
  ! Determine whether a dataset is indexed by
  ! cell ids
  !
  ! Author: Glenn Hammond
  ! Date: 05/03/13
  !

  use Option_module
  use HDF5_Aux_module

  implicit none

  class(dataset_common_hdf5_type) :: dataset
  type(option_type) :: option

  PetscBool :: DatasetCommonHDF5IsCellIndexed

  DatasetCommonHDF5IsCellIndexed = &
    .not.HDF5GroupExists(dataset%filename,dataset%hdf5_dataset_name,option)

end function DatasetCommonHDF5IsCellIndexed

! ************************************************************************** !

function DatasetCommonHDF5GetPointer(dataset_list, dataset_name, &
                                     debug_string, option)
  !
  ! Returns the pointer to the dataset named "name"
  !
  ! Author: Glenn Hammond
  ! Date: 05/03/13
  !

  use Option_module
  use String_module

  class(dataset_base_type), pointer :: dataset_list
  character(len=MAXWORDLENGTH) :: dataset_name
  character(len=MAXSTRINGLENGTH) :: debug_string
  type(option_type) :: option

  class(dataset_common_hdf5_type), pointer :: DatasetCommonHDF5GetPointer

  class(dataset_base_type), pointer :: dataset

  nullify(DatasetCommonHDF5GetPointer)
  dataset => DatasetBaseGetPointer(dataset_list, dataset_name, &
                                   debug_string, option)
  select type(dataset)
    class is (dataset_common_hdf5_type)
      DatasetCommonHDF5GetPointer => dataset
    class default
      option%io_buffer = 'Dataset "' // trim(dataset_name) // '" in "' // &
             trim(debug_string) // '" not of type Common HDF5.'
      call PrintErrMsg(option)
  end select

end function DatasetCommonHDF5GetPointer

! ************************************************************************** !

function DatasetCommonHDF5GetNameInfo(this)
  !
  ! Returns naming information for dataset
  !
  ! Author: Glenn Hammond
  ! Date: 02/20/18
  !
  implicit none

  class(dataset_common_hdf5_type) :: this

  character(len=MAXSTRINGLENGTH) :: DatasetCommonHDF5GetNameInfo

  character(len=MAXSTRINGLENGTH) :: string

  string = DatasetBaseGetNameInfo(this)
  if (len_trim(this%hdf5_dataset_name) > 0) then
    string = trim(string) // ' HDF5_DATASET_NAME: "' // &
             trim(this%hdf5_dataset_name) // '"'
  endif
  DatasetCommonHDF5GetNameInfo = string

end function DatasetCommonHDF5GetNameInfo

! ************************************************************************** !

subroutine DatasetCommonHDF5Print(this,option)
  !
  ! Prints dataset info
  !
  ! Author: Glenn Hammond
  ! Date: 10/22/13
  !

  use Option_module

  implicit none

  class(dataset_common_hdf5_type) :: this
  type(option_type) :: option

  if (len_trim(this%hdf5_dataset_name) > 0) then
    write(option%fid_out,'(10x,''HDF5 Dataset Name: '',a)') &
      trim(this%hdf5_dataset_name)
  endif
  if (this%realization_dependent) then
    write(option%fid_out,'(10x,''Realization Dependent: yes'')')
  else
    write(option%fid_out,'(10x,''Realization Dependent: no'')')
  endif
  if (this%is_cell_indexed) then
    write(option%fid_out,'(10x,''Cell Indexed: yes'')')
  else
    write(option%fid_out,'(10x,''Cell Indexed: no'')')
  endif
  write(option%fid_out,'(10x,''Maximum Buffer Size: '',i3)') &
    this%max_buffer_size

end subroutine DatasetCommonHDF5Print

! ************************************************************************** !

subroutine DatasetCommonHDF5Strip(this)
  !
  ! Strips allocated objects within common hdf5 dataset
  ! object
  !
  ! Author: Glenn Hammond
  ! Date: 05/03/13
  !

  implicit none

  class(dataset_common_hdf5_type) :: this

  call DatasetBaseStrip(this)

end subroutine DatasetCommonHDF5Strip

! ************************************************************************** !

subroutine DatasetCommonHDF5Destroy(this)
  !
  ! Destroys a dataset
  !
  ! Author: Glenn Hammond
  ! Date: 01/12/11
  !

  implicit none

  class(dataset_common_hdf5_type), pointer :: this

  if (.not.associated(this)) return

  call DatasetCommonHDF5Strip(this)

  deallocate(this)
  nullify(this)

end subroutine DatasetCommonHDF5Destroy

end module Dataset_Common_HDF5_class
